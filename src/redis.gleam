import gleam/erlang/process
import gleam/option
import valkyrie

const default_timeout = 1000

pub fn create_supervised_pool() {
  let name = process.new_name("connection_pool")

  #(
    name,
    valkyrie.default_config()
      |> valkyrie.supervised_pool(
        size: 10_000,
        name: option.Some(name),
        timeout: default_timeout,
      ),
  )
}

pub fn enqueue_payments(body: List(String), conn: valkyrie.Connection) {
  valkyrie.lpush(conn, "payments_created", body, default_timeout)
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
