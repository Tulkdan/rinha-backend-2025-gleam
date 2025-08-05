import birl
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/result

pub type PaymentRequest {
  PaymentRequest(correlation_id: String, amount: Float, requested_at: birl.Time)
}

pub fn to_dict(payment: PaymentRequest) -> dict.Dict(String, String) {
  dict.new()
  |> dict.insert(payment.correlation_id, payment |> to_json |> json.to_string)
}

pub fn to_json(payment: PaymentRequest) -> json.Json {
  [
    #("correlationId", json.string(payment.correlation_id)),
    #("amount", json.float(payment.amount)),
    #("requestedAt", json.string(payment.requested_at |> birl.to_iso8601)),
  ]
  |> json.object
}

pub fn from_json_string(payment: String) {
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

  json.parse(payment, parse)
}
