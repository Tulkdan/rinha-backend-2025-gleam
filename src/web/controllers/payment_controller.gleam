import birl
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option
import gleam/string_tree
import model.{type PaymentRequest, PaymentRequest}
import redis
import valkyrie/resp
import web/server
import wisp

fn decode_payment_body(
  body: dynamic.Dynamic,
  cb: fn(PaymentRequest) -> wisp.Response,
) {
  let decoder = {
    use correlation <- decode.field("correlationId", decode.string)
    use amount <- decode.field("amount", decode.float)

    decode.success(PaymentRequest(
      correlation_id: correlation,
      amount: amount,
      requested_at: birl.now(),
      provider: option.None,
    ))
  }
  case decode.run(body, decoder) {
    Ok(body) -> cb(body)
    Error(_) -> wisp.bad_request()
  }
}

pub fn handle_payment_post(
  req: wisp.Request,
  ctx: server.Context,
) -> response.Response(wisp.Body) {
  use json <- wisp.require_json(req)
  use body <- decode_payment_body(json)

  let data_to_insert =
    body
    |> model.to_json
    |> json.to_string
    |> list.wrap

  let assert Ok(_) =
    echo ctx.valkye_conn
      |> redis.enqueue_payments(data_to_insert)

  wisp.no_content()
}

pub fn get_all_payments(
  _req: wisp.Request,
  ctx: server.Context,
) -> response.Response(wisp.Body) {
  case redis.get_all_saved_data(ctx.valkye_conn) {
    Ok(data) -> {
      let response =
        data
        |> dict.values
        |> list.map(fn(value) {
          let assert resp.BulkString(v) = value
          let assert Ok(json_data) = model.from_json_string(v)
          json_data
        })
        |> json.array(of: model.to_json)
        |> json.to_string_tree

      wisp.ok()
      |> wisp.json_body(response)
    }
    Error(_) ->
      wisp.no_content()
      |> wisp.json_body(string_tree.from_string("[]"))
  }
}

pub fn purge_payments(
  _req: wisp.Request,
  ctx: server.Context,
) -> response.Response(wisp.Body) {
  case redis.delete_saved_data(ctx.valkye_conn) {
    _ -> wisp.no_content()
  }
}
