import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/list
import redis
import web/server
import wisp

type PaymentRequest {
  PaymentRequest(correlation_id: String, amount: Float)
}

fn decode_payment_body(
  body: dynamic.Dynamic,
  cb: fn(PaymentRequest) -> wisp.Response,
) {
  let decoder = {
    use correlation <- decode.field("correlationId", decode.string)
    use amount <- decode.field("amount", decode.float)

    decode.success(PaymentRequest(correlation_id: correlation, amount: amount))
  }
  case decode.run(body, decoder) {
    Ok(body) -> cb(body)
    Error(_) -> wisp.bad_request()
  }
}

pub fn handle_payment_post(req: wisp.Request, ctx: server.Context) {
  use json <- wisp.require_json(req)
  use body <- decode_payment_body(json)

  let assert Ok(_) =
    echo json.object([
        #("correlationId", json.string(body.correlation_id)),
        #("amount", json.float(body.amount)),
      ])
      |> json.to_string
      |> list.wrap
      |> redis.enqueue_payments(ctx.valkye_conn)

  wisp.no_content()
}
