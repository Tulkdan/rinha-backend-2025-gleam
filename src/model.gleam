import birl

pub type PaymentRequest {
  PaymentRequest(correlation_id: String, amount: Float, requested_at: birl.Time)
}
