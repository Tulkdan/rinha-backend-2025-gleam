import birl
import gleam/bool
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option
import gleam/order
import gleam/string_tree
import models/count_provider
import models/payment_request.{type PaymentRequest, PaymentRequest}
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
    |> payment_request.to_json
    |> json.to_string
    |> list.wrap

  let assert Ok(_) =
    ctx.valkye_conn
    |> redis.enqueue_payments(data_to_insert)

  wisp.no_content()
}

fn get_all_payments_response(
  default: count_provider.CountProvider,
  fallback: count_provider.CountProvider,
) -> json.Json {
  [
    #("default", count_provider.to_json(default)),
    #("fallback", count_provider.to_json(fallback)),
  ]
  |> json.object
}

pub fn get_all_payments(
  req: wisp.Request,
  ctx: server.Context,
) -> response.Response(wisp.Body) {
  let params =
    req
    |> wisp.get_query
    |> list.map(fn(param) {
      let #(key, value) = param
      let assert Ok(v) = value |> birl.parse

      #(key, v)
    })
    |> dict.from_list

  use <- bool.guard(
    when: !dict.has_key(params, "from"),
    return: wisp.ok()
      |> wisp.json_body(
        get_all_payments_response(
          count_provider.new("default"),
          count_provider.new("fallback"),
        )
        |> json.to_string_tree,
      ),
  )

  use <- bool.guard(
    when: !dict.has_key(params, "to"),
    return: wisp.ok()
      |> wisp.json_body(
        get_all_payments_response(
          count_provider.new("default"),
          count_provider.new("fallback"),
        )
        |> json.to_string_tree,
      ),
  )

  let assert Ok(from) = dict.get(params, "from")
  let assert Ok(to) = dict.get(params, "to")

  let data_in_redis = case redis.get_all_saved_data(ctx.valkye_conn) {
    Ok(data) ->
      data
      |> dict.values
      |> list.filter_map(fn(value) {
        let assert resp.BulkString(v) = value
        let assert Ok(json_data) = payment_request.from_json_string(v)

        use <- bool.guard(
          when: birl.compare(json_data.requested_at, from) == order.Lt,
          return: Error(Nil),
        )
        use <- bool.guard(
          when: birl.compare(json_data.requested_at, to) == order.Gt,
          return: Error(Nil),
        )

        Ok(json_data)
      })
    Error(_) -> []
  }

  use <- bool.guard(
    when: data_in_redis == [],
    return: wisp.no_content()
      |> wisp.json_body(string_tree.from_string("[]")),
  )

  let grouped_by_provider =
    data_in_redis
    |> list.group(by: fn(data) {
      case data {
        payment_request.PaymentRequest(provider: option.Some("default"), ..) ->
          "default"
        _ -> "fallback"
      }
    })

  let default_requests =
    count_provider.new("default")
    |> count_provider.count_provider(grouped_by_provider)
  let fallback_requests =
    count_provider.new("fallback")
    |> count_provider.count_provider(grouped_by_provider)

  wisp.ok()
  |> wisp.json_body(
    get_all_payments_response(default_requests, fallback_requests)
    |> json.to_string_tree,
  )
}

pub fn purge_payments(
  _req: wisp.Request,
  ctx: server.Context,
) -> response.Response(wisp.Body) {
  case redis.delete_saved_data(ctx.valkye_conn) {
    _ -> wisp.no_content()
  }
}
