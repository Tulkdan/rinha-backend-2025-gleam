import gleam/dict
import gleam/json
import gleam/list
import models/payment_request.{type PaymentRequest}

pub type CountProvider {
  CountProvider(provider: String, total_requests: Int, total_amount: Float)
}

pub fn new(provider: String) -> CountProvider {
  CountProvider(provider: provider, total_amount: 0.0, total_requests: 0)
}

pub fn count_provider(
  count: CountProvider,
  payments: dict.Dict(String, List(PaymentRequest)),
) -> CountProvider {
  case dict.get(payments, count.provider) {
    Error(_) -> count
    Ok(data) ->
      data
      |> list.fold(count, fn(acc, d) {
        CountProvider(
          ..acc,
          total_requests: acc.total_requests + 1,
          total_amount: acc.total_amount +. d.amount,
        )
      })
  }
}

pub fn to_json(count: CountProvider) -> json.Json {
  [
    #("totalRequests", json.int(count.total_requests)),
    #("totalAmount", json.float(count.total_amount)),
  ]
  |> json.object()
}
