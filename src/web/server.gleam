import gleam/erlang/process
import processor
import valkyrie

pub type Context {
  Context(
    valkye_conn: valkyrie.Connection,
    // worker_subject: process.Subject(processor.Message),
  )
}
