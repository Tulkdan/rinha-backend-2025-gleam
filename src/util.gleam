import envoy

pub fn get_env_var(env: String, default: String) -> String {
  case envoy.get(env) {
    Error(_) -> default
    Ok(val) -> val
  }
}
