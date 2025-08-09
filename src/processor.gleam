import gleam/bool
import gleam/erlang/process
import gleam/option
import gleam/otp/actor
import gleam/otp/supervision
import integrations/provider
import models/payment_request
import redis
import valkyrie

pub type Processor {
  Processor(
    redis_conn: valkyrie.Connection,
    name: option.Option(process.Name(Message)),
    providers: List(provider.ProviderConfig),
    selected_provider: provider.ProviderConfig,
  )
}

pub type Message {
  ServerTick
  HealthCheck
}

pub fn new(conn: valkyrie.Connection) -> Processor {
  Processor(
    redis_conn: conn,
    name: option.None,
    providers: [],
    selected_provider: provider.ProviderConfig(
      url: "",
      min_response_time: -1,
      name: "",
    ),
  )
}

pub fn named(processor: Processor, name: process.Name(Message)) -> Processor {
  Processor(..processor, name: option.Some(name))
}

pub fn providers(
  processor: Processor,
  providers: List(provider.ProviderConfig),
) -> Processor {
  Processor(..processor, providers: providers)
}

fn selected_provider(
  processor: Processor,
  provider: provider.ProviderConfig,
) -> Processor {
  Processor(..processor, selected_provider: provider)
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
      process.spawn(fn() {
        case redis.read_queue_payments(state.redis_conn) {
          "" -> Nil
          data -> {
            let _ = case integrate_data(state, data) {
              Error(_) ->
                state.redis_conn
                |> redis.enqueue_payments([data])
              Ok(message) ->
                state.redis_conn
                |> redis.save_data(message)
            }
            Nil
          }
        }
      })

      actor.continue(state)
    }
    HealthCheck -> {
      let provider =
        get_faster_healthcheck(state.providers, state.selected_provider)

      state
      |> selected_provider(provider)
      |> actor.continue
    }
  }
}

pub fn loop_worker(subject: process.Subject(Message), processor_time: Int) {
  process.send(subject, ServerTick)
  process.sleep(processor_time)
  loop_worker(subject, processor_time)
}

pub fn loop_healthcheck(subject: process.Subject(Message)) {
  process.send(subject, HealthCheck)
  process.sleep(5000)
  loop_healthcheck(subject)
}

fn integrate_data(processor: Processor, data: String) {
  let assert Ok(message) = payment_request.from_json_string(data)

  let body_to_send = message |> provider.create_body

  case provider.send_request(processor.selected_provider, body_to_send) {
    Ok(_) -> {
      message
      |> payment_request.set_provider(processor.selected_provider.name)
      |> payment_request.to_dict
      |> Ok
    }
    _ -> Error(Nil)
  }
}

fn get_faster_healthcheck(
  providers: List(provider.ProviderConfig),
  acc: provider.ProviderConfig,
) -> provider.ProviderConfig {
  case providers {
    [] -> acc
    [provider, ..rest] ->
      case provider.health_check(provider) {
        Error(_) -> acc
        Ok(data) -> {
          use <- bool.lazy_guard(when: acc.url == "", return: fn() {
            get_faster_healthcheck(
              rest,
              provider.ProviderConfig(
                ..provider,
                min_response_time: data.min_response_time,
              ),
            )
          })

          use <- bool.lazy_guard(
            when: acc.min_response_time <= data.min_response_time,
            return: fn() { get_faster_healthcheck(rest, acc) },
          )

          get_faster_healthcheck(
            rest,
            provider.ProviderConfig(
              ..provider,
              min_response_time: data.min_response_time,
            ),
          )
        }
      }
  }
}
