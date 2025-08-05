import gleam/bool
import gleam/erlang/process
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
  let providers =
    providers_env
    |> string.split(",")
    |> list.filter(fn(url) { "" != url })
    |> list.map(fn(url) { provider.ProviderConfig(url: url) })
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

  process.spawn(fn() {
    use <- bool.guard(when: !has_providers, return: Ok(Nil))

    worker_name
    |> process.named_subject
    |> processor.loop_worker
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
