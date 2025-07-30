import mist
import web/router
import web/server
import wisp
import wisp/wisp_mist

pub fn create_server_supervised(ctx: server.Context) {
  wisp.configure_logger()

  router.handle_request(_, ctx)
  |> wisp_mist.handler("secret")
  |> mist.new
  |> mist.port(8000)
  |> mist.supervised
}
