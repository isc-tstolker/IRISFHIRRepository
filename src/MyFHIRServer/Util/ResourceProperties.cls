/// Resource properties helper
Class MyFHIRServer.Util.ResourceProperties
{

/// Order FHIR resource properties according to the spec
ClassMethod FHIROrderResourceProperties(schema As HS.FHIRServer.Schema, resource As %DynamicObject) As %DynamicObject
{
    do ##class(HS.FHIRServer.Util.JSONToXML).JSONToXML(resource, .pOutStream, schema)
    return ##class(HS.FHIRServer.Util.XMLToJSON).XMLToJSON(.pOutStream, schema)
}

}
