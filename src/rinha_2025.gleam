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

  let worker_name = process.new_name("worker_pool")
  let worker_pool_supervised =
    processor.new(valky)
    |> processor.named(worker_name)
    |> processor.supervised

  let ctx = server.Context(valkye_conn: valky)

  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(valkey_pool)
    |> supervisor.add(web.create_server_supervised(ctx))
    |> supervisor.add(worker_pool_supervised)
    |> supervisor.start

  process.spawn(fn() {
    worker_name
    |> process.named_subject
    |> processor.loop_worker
  })

  process.sleep_forever()
}
