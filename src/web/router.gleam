import gleam/http
import web/controllers/payment_controller
import web/middleware
import web/server
import wisp

pub fn handle_request(req: wisp.Request, ctx: server.Context) -> wisp.Response {
  use req <- middleware.middleware(req)

  case wisp.path_segments(req) {
    ["payments"] -> {
      use <- wisp.require_method(req, http.Post)
      payment_controller.handle_payment_post(req, ctx)
    }
    ["payments-summary"] -> {
      use <- wisp.require_method(req, http.Get)
      todo
    }
    _ -> wisp.not_found()
  }
}
