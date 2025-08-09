import gleam/bool
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/static_supervisor as supervisor
import gleam/string
import integrations/provider
import processor
import redis
import util
import valkyrie
import web/server
import web/web

pub fn main() -> Nil {
  let redis_host = util.get_env_var("REDIS_CONN", "localhost")
  let providers_env = util.get_env_var("PROVIDERS", "")
  let assert Ok(processor_time) =
    util.get_env_var("PROCESSOR_TIME", "100")
    |> int.parse

  let providers =
    providers_env
    |> string.split(",")
    |> list.filter(fn(url) { "" != url })
    |> list.map(fn(url) {
      let provider_name = case string.contains(url, contain: "default") {
        True -> "default"
        _ -> "fallback"
      }
      provider.ProviderConfig(
        url: url,
        min_response_time: -1,
        name: provider_name,
      )
    })
  let has_providers = list.length(providers) > 0

  let #(valkey_pool_name, valkey_pool) =
    redis.create_supervised_pool(redis_host)
  let valky = valkyrie.named_connection(valkey_pool_name)

  let ctx = server.Context(valkye_conn: valky)

  use <- bool.lazy_guard(when: has_providers == False, return: fn() {
    let assert Ok(_) =
      supervisor.new(supervisor.OneForOne)
      |> supervisor.add(valkey_pool)
      |> supervisor.add(web.create_server_supervised(ctx))
      |> supervisor.start

    process.sleep_forever()
  })

  let worker_name = process.new_name("worker_pool")
  let worker_pool_supervised =
    processor.new(valky)
    |> processor.named(worker_name)
    |> processor.providers(providers)
    |> processor.supervised

  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(valkey_pool)
    |> supervisor.add(web.create_server_supervised(ctx))
    |> supervisor.add(worker_pool_supervised)
    |> supervisor.start

  process.spawn(fn() {
    worker_name
    |> process.named_subject
    |> processor.loop_worker(processor_time)
  })

  process.spawn(fn() {
    worker_name
    |> process.named_subject
    |> processor.loop_healthcheck
  })

  process.sleep_forever()
}
