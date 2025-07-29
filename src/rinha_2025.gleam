import gleam/erlang/process
import gleam/otp/static_supervisor as supervisor
import redis
import valkyrie
import web/server
import web/web

pub fn main() -> Nil {
  let #(valkey_pool_name, valkey_pool) = redis.create_supervised_pool()

  let ctx =
    server.Context(valkye_conn: valkyrie.named_connection(valkey_pool_name))

  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(valkey_pool)
    |> supervisor.add(web.create_server_supervised(ctx))
    |> supervisor.start

  process.sleep_forever()
}
