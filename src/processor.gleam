import gleam/erlang/process
import gleam/option
import gleam/otp/actor
import gleam/otp/supervision
import gleam/string
import integrations/provider
import models/payment_request
import redis
import valkyrie

pub type Processor {
  Processor(
    redis_conn: valkyrie.Connection,
    name: option.Option(process.Name(Message)),
    connections: Int,
    providers: List(provider.ProviderConfig),
  )
}

pub type Message {
  ServerTick
}

pub fn new(conn: valkyrie.Connection) -> Processor {
  Processor(redis_conn: conn, name: option.None, connections: 1, providers: [])
}

pub fn named(processor: Processor, name: process.Name(Message)) -> Processor {
  Processor(..processor, name: option.Some(name))
}

pub fn connections(processor: Processor, connections: Int) -> Processor {
  Processor(..processor, connections: connections)
}

pub fn providers(
  processor: Processor,
  providers: List(provider.ProviderConfig),
) -> Processor {
  Processor(..processor, providers: providers)
}

pub fn start(processor: Processor) {
  let ac =
    processor
    |> actor.new
    |> actor.on_message(handle_message)

  case processor.name {
    option.None -> ac
    option.Some(name) -> ac |> actor.named(name)
  }
  |> actor.start
}

pub fn supervised(processor: Processor) {
  supervision.supervisor(fn() { start(processor) })
}

fn handle_message(state: Processor, message: Message) {
  case message {
    ServerTick -> {
      case redis.read_queue_payments(state.redis_conn) {
        "" -> actor.continue(state)
        data -> {
          process.spawn(fn() { integrate_data(state, data) })
          actor.continue(state)
        }
      }
    }
  }
}

pub fn loop_worker(subject: process.Subject(Message)) {
  process.send(subject, ServerTick)
  process.sleep(200)
  loop_worker(subject)
}

fn integrations(
  providers: List(provider.ProviderConfig),
  body: String,
) -> Result(provider.ProviderConfig, Bool) {
  case providers {
    [] -> Error(False)
    [provider, ..rest] -> {
      echo "Trying provider -> " <> provider.url
      case provider.send_request(provider, body) {
        Ok(_) -> Ok(provider)
        _ -> integrations(rest, body)
      }
    }
  }
}

fn integrate_data(processor: Processor, data: String) {
  echo "Trying to integrate " <> data
  let assert Ok(message) = payment_request.from_json_string(data)

  let body_to_send = message |> provider.create_body

  case integrations(processor.providers, body_to_send) {
    Error(_) -> {
      echo "Failed, reenqueuing it"

      processor.redis_conn
      |> redis.enqueue_payments([data])
    }
    Ok(provider_processed) -> {
      echo "Success, saving it"

      let save_provider = case
        string.contains(provider_processed.url, contain: "default")
      {
        True -> "default"
        _ -> "fallback"
      }

      processor.redis_conn
      |> redis.save_data(
        message
        |> payment_request.set_provider(save_provider)
        |> payment_request.to_dict,
      )
    }
  }
}
