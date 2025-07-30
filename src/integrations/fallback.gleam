import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/result
import integrations/default

pub fn fallback_provider_send_request(body: String) {
  let assert Ok(request) = request.to("http://localhost:8002/payments")

  use response <- result.try(
    request
    |> request.set_header("content-type", "application/json")
    |> request.set_body(body)
    |> request.set_method(http.Post)
    |> httpc.send,
  )

  default.parse_http_response(response)
}
