import birl
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/json
import gleam/result
import models/payment_request.{type PaymentRequest}

pub type ProviderConfig {
  ProviderConfig(url: String, min_response_time: Int, name: String)
}

pub fn create_body(body: PaymentRequest) -> String {
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

pub type HealthcheckResponse {
  HealthcheckResponse(failing: Bool, min_response_time: Int)
}

fn health_check_req(req: request.Request(String)) {
  use response <- result.try(
    req
    |> request.set_header("content-type", "application/json")
    |> request.set_method(http.Get)
    |> httpc.send,
  )

  Ok(response.body)
}

pub fn health_check(
  provider: ProviderConfig,
) -> Result(HealthcheckResponse, httpc.HttpError) {
  let assert Ok(request) =
    request.to(provider.url <> "/payments/service-health")

  case health_check_req(request) {
    Error(e) -> Error(e)
    Ok(body) -> {
      let parser = {
        use failing <- decode.field("failing", decode.bool)
        use min_response_time <- decode.field("minResponseTime", decode.int)

        decode.success(HealthcheckResponse(
          failing: failing,
          min_response_time: min_response_time,
        ))
      }

      let assert Ok(data) = json.parse(body, parser)
      Ok(data)
    }
  }
}
