import birl
import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/json
import gleam/otp/actor
import gleam/result
import integrations/default
import integrations/fallback
import model.{type PaymentRequest, PaymentRequest}
import redis
import valkyrie

pub type Message {
  Process(element: PaymentRequest)
}

pub fn create_worker_to_read_messages() {
  let name = process.new_name("worker_process")

  actor.new(PaymentRequest(
    amount: 0.0,
    correlation_id: "",
    requested_at: birl.now(),
  ))
  |> actor.named(name)
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(state: PaymentRequest, message: Message) {
  echo "inside on message"
  case message {
    Process(data) -> {
      let body_to_send = data |> default.create_body

      case default.default_provider_send_request(body_to_send) {
        Ok(_) -> actor.continue(data)
        Error(_) -> {
          echo "failed to make request"
          case fallback.fallback_provider_send_request(body_to_send) {
            Ok(_) -> actor.continue(data)
            Error(_) -> {
              echo "failed to make request"
              actor.continue(data)
            }
          }
        }
      }
    }
  }
}

pub fn loop_worker(subject: process.Subject(Message), conn: valkyrie.Connection) {
  echo "inside pool"
  case redis.read_queue_payments(conn) {
    "" -> Nil
    data -> {
      let assert Ok(message) = parse_data_redis(data)
      process.send(subject, Process(message))
    }
  }

  process.sleep(2000)
  loop_worker(subject, conn)
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
