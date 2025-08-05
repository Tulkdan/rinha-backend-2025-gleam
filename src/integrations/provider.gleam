import birl
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/json
import gleam/result
import model

pub type ProviderConfig {
  ProviderConfig(url: String)
}

pub fn create_body(body: model.PaymentRequest) -> String {
  json.object([
    #("correlationId", json.string(body.correlation_id)),
    #("amount", json.float(body.amount)),
    #("requestedAt", json.string(birl.to_iso8601(body.requested_at))),
  ])
  |> json.to_string
}

pub fn send_request(provider: ProviderConfig, body: String) {
  let assert Ok(request) = request.to(provider.url <> "/payments")

  use response <- result.try(
    request
    |> request.set_header("content-type", "application/json")
    |> request.set_body(body)
    |> request.set_method(http.Post)
    |> httpc.send,
  )

  parse_http_response(response)
}

pub fn parse_http_response(
  data: response.Response(String),
) -> Result(String, httpc.HttpError) {
  case data.status {
    status if status >= 200 && status < 300 -> Ok(data.body)
    _ -> Error(httpc.ResponseTimeout)
  }
}
