import gleam/bool
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
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
  let assert Ok(processor_qtt) =
    util.get_env_var("PROCESSOR_QTT", "0")
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

  let worker_name = process.new_name("worker_pool")
  let worker_pool_supervised =
    processor.new(valky)
    |> processor.named(worker_name)
    |> processor.providers(providers)
    |> processor.supervised

  let ctx = server.Context(valkye_conn: valky)

  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(valkey_pool)
    |> supervisor.add(web.create_server_supervised(ctx))
    |> create_supervisor_with_processor(worker_pool_supervised, has_providers)
    |> supervisor.start

  use <- bool.lazy_guard(when: !has_providers, return: process.sleep_forever)

  list.repeat(Nil, processor_qtt)
  |> list.map(fn(a) {
    process.spawn(fn() {
      worker_name
      |> process.named_subject
      |> processor.loop_worker(processor_time)
    })
    a
  })

  process.spawn(fn() {
    worker_name
    |> process.named_subject
    |> processor.loop_healthcheck
  })

  process.sleep_forever()
}

fn create_supervisor_with_processor(
  manager: supervisor.Builder,
  processor: supervision.ChildSpecification(process.Subject(processor.Message)),
  has_processor: Bool,
) {
  use <- bool.guard(when: !has_processor, return: manager)

  manager
  |> supervisor.add(processor)
}
