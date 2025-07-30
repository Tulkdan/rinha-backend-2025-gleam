import birl
import gleam/erlang/process
import gleam/otp/actor
import integrations/default
import integrations/fallback
import model.{type PaymentRequest, PaymentRequest}

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
