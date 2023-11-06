/// Enum for different response scenarios from the Adyen payment flow to flutter.
enum AdyenResponse {
  AuthenticationFinished,
  AuthenticationNotRequired,
  Authorised,
  Cancelled,
  ChallengeShopper,
  Error,
  IdentifyShopper,
  Pending,
  PresentToShopper,
  Received,
  RedirectShopper,
  Refused
}
