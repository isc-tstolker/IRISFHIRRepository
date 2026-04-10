/// Customizable class for finding the base URL of a FHIR/CSP request.
/// Add a custom GetBaseURL(pRequest,pLocalBase) method here to override the default from HS.FHIRServer.Util.BaseURL.
Class HS.Local.FHIRServer.Util.BaseURL Extends HS.FHIRServer.Util.BaseURL
{

ClassMethod GetBaseURL(pRequest As %RegisteredObject = {$$$NULLOREF}, Output pLocalBase As %String) As %String
{
  Set protocol = ""
  If pRequest.IsDefinedCgiEnv("HTTP_X_FORWARDED_PROTO") Set protocol = pRequest.GetCgiEnv("HTTP_X_FORWARDED_PROTO")

  Set port = ""
  If pRequest.IsDefinedCgiEnv("HTTP_X_FORWARDED_PORT") Set port = pRequest.GetCgiEnv("HTTP_X_FORWARDED_PORT")

  If protocol = "https" && (port = "443") {
    Set pRequest.CgiEnvs("HTTP_X_FORWARDED_PORT") = ""
  }

  Return ##super(pRequest, .pLocalBase)
}

}
