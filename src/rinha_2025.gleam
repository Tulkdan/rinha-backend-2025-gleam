import gleam/erlang/process
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import processor
import redis
import valkyrie
import web/server
import web/web

pub fn main() -> Nil {
  let #(valkey_pool_name, valkey_pool) = redis.create_supervised_pool()
  let valky = valkyrie.named_connection(valkey_pool_name)
  let worker_pool = processor.create_worker_to_read_messages()

  let ctx = server.Context(valkye_conn: valky)

  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(valkey_pool)
    |> supervisor.add(web.create_server_supervised(ctx))
    |> supervisor.add(supervision.worker(fn() { worker_pool }))
    |> supervisor.start

  let assert Ok(pool) = worker_pool
  processor.loop_worker(pool.data, valky)

  process.sleep_forever()
}
