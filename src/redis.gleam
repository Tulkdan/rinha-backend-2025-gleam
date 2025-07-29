import gleam/erlang/process
import gleam/option
import valkyrie

pub fn create_supervised_pool() {
  let name = process.new_name("connection_pool")

  #(
    name,
    valkyrie.default_config()
      |> valkyrie.supervised_pool(
        size: 10,
        name: option.Some(name),
        timeout: 1000,
      ),
  )
}

pub fn enqueue_payments(body: List(String), conn: valkyrie.Connection) {
  valkyrie.lpush(conn, "payments_created", body, 1000)
}
