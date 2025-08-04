import birl
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/json
import gleam/option
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import integrations/default
import integrations/fallback
import model.{PaymentRequest}
import redis
import valkyrie

pub type Processor {
  Processor(
    redis_conn: valkyrie.Connection,
    name: option.Option(process.Name(Message)),
  )
}

pub type Message {
  ServerTick
}

pub fn new(conn: valkyrie.Connection) {
  Processor(redis_conn: conn, name: option.None)
}

pub fn named(processor: Processor, name: process.Name(Message)) {
  Processor(..processor, name: option.Some(name))
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
  echo "inside on message"
  case message {
    ServerTick -> {
      case redis.read_queue_payments(state.redis_conn) {
        "" -> actor.continue(state)
        data -> {
          let assert Ok(message) = parse_data_redis(data)

          let body_to_send = message |> default.create_body

          case default.default_provider_send_request(body_to_send) {
            Ok(_) -> actor.continue(state)
            Error(_) -> {
              echo "failed to make request"
              case fallback.fallback_provider_send_request(body_to_send) {
                Ok(_) -> actor.continue(state)
                Error(_) -> {
                  echo "failed to make request"
                  actor.continue(state)
                }
              }
            }
          }

          actor.continue(state)
        }
      }
    }
  }
}

pub fn loop_worker(subject: process.Subject(Message)) {
  echo "inside pool"
  process.send(subject, ServerTick)
  process.sleep(2000)
  loop_worker(subject)
}

fn parse_data_redis(message: String) {
  echo message
  let parse = {
    use amount <- decode.field("amount", decode.float)
    use correlation_id <- decode.field("correlationId", decode.string)
    use requested_at <- decode.field("requestedAt", decode.string)

    decode.success(PaymentRequest(
      amount: amount,
      correlation_id: correlation_id,
      requested_at: requested_at
        |> birl.parse
        |> result.unwrap(birl.now()),
    ))
  }

  json.parse(message, parse)
}
