import gleam/dict
import gleam/erlang/process
import gleam/option
import valkyrie

const default_timeout = 1000

const default_key = "payments"

pub fn create_supervised_pool(host: String) {
  let name = process.new_name("connection_pool")

  #(
    name,
    valkyrie.default_config()
      |> valkyrie.host(host)
      |> valkyrie.supervised_pool(
        size: 10_000,
        name: option.Some(name),
        timeout: default_timeout,
      ),
  )
}

pub fn enqueue_payments(conn: valkyrie.Connection, body: List(String)) {
  conn
  |> valkyrie.lpush("payments_created", body, default_timeout)
}

pub fn read_queue_payments(conn: valkyrie.Connection) -> String {
  case valkyrie.exists(conn, ["payments_created"], default_timeout) {
    Ok(qtt) -> {
      case valkyrie.rpop(conn, "payments_created", qtt, default_timeout) {
        Ok(data) -> data
        Error(_) -> ""
      }
    }
    Error(_) -> ""
  }
}

pub fn save_data(conn: valkyrie.Connection, body: dict.Dict(String, String)) {
  conn
  |> valkyrie.hset(default_key, body, default_timeout)
}

pub fn get_all_saved_data(conn: valkyrie.Connection) {
  conn
  |> valkyrie.hgetall(default_key, default_timeout)
}
