Include HS.FHIRServer

/// FHIR Interactions handler
Class MyFHIRServer.Storage.Json.Interactions Extends (HS.FHIRServer.Storage.Json.Interactions, MyFHIRServer.Util.IdentifierHelper)
{

Parameter OperationHandlerClass = "MyFHIRServer.Storage.BuiltInOperations";

Parameter BatchHandlerClass As STRING = "HS.FHIRServer.Storage.Json.BundleProcessor";

Parameter ResourceValidatorClass As STRING = "MyFHIRServer.Util.ResourceValidator";

Parameter OAuth2TokenHandlerClass As STRING = "HS.FHIRServer.Util.OAuth2Token";

Property strategy As MyFHIRServer.Storage.Json.InteractionsStrategy;

Property FHIRService As HS.FHIRServer.API.Service;

/// Gather some  information needed for Trigger processing
Method OnBeforeRequest(pFHIRService As HS.FHIRServer.API.Service, pFHIRRequest As HS.FHIRServer.API.Data.Request, pTimeout As %Integer)
{
	set ..FHIRService = pFHIRService

	if (pFHIRRequest.Json '= "")
	{
		set resourceValidator = ##class(HS.FHIRServer.Util.ResourceValidator).%New(pFHIRService.Schema)

		do resourceValidator.ValidateResource(pFHIRRequest.Json)
		set pFHIRRequest.Json = ##class(MyFHIRServer.Util.ResourceProperties).FHIROrderResourceProperties(pFHIRService.Schema, pFHIRRequest.Json)
	}

	do ##super(pFHIRService, pFHIRRequest, pTimeout)
}

/// Fix resource order for create and update
Method OnAfterRequest(pFHIRService As HS.FHIRServer.API.Service, pFHIRRequest As HS.FHIRServer.API.Data.Request, pFHIRResponse As HS.FHIRServer.API.Data.Response)
{
	if $ISOBJECT(pFHIRResponse.Json)
	{
		Set pFHIRResponse.Json = ##class(MyFHIRServer.Util.ResourceProperties).FHIROrderResourceProperties(pFHIRService.Schema, pFHIRResponse.Json)
	}
}

/// Handle create interaction
Method Add(pResourceObj As %DynamicObject, pResourceIdToAssign As %String = "", pHttpMethod As %String = "POST") As %String
{
	$$$FSLog("Add resource type: "_pResourceObj.resourceType_", HTTP method: " _ pHttpMethod)

	set pResourceIdToAssign = $ZCONVERT($System.Util.CreateGUID(), "L")

	do ##class(MyFHIRServer.Util.RefIntHelper).ValidateReferences(pResourceObj, ..strategy)

	if $ISOBJECT(pResourceObj.identifier)
	{
		// Check for identifier uniqueness
		do ..EnsureUniqueIdentifiersBeforeWrite($THIS, pResourceObj)
	}

	return ##super(pResourceObj, pResourceIdToAssign, pHttpMethod)
}

/// Handle Update interaction
Method Update(pResourceObj As %DynamicObject) As %String
{
	$$$FSLog("Update resource type: "_ pResourceObj.resourceType _ " with id " _ pResourceObj.id)
	
	do ##class(MyFHIRServer.Util.RefIntHelper).ValidateReferences(pResourceObj, ..strategy)

	if $ISOBJECT(pResourceObj.identifier)
	{
		// Check for identifier uniqueness
		do ..EnsureUniqueIdentifiersBeforeWrite($THIS, pResourceObj)
	}
	
	return ##super(pResourceObj)

}

/// Read interaction handler, orders the properties!
Method Read(pResourceType As %String, pResourceId As %String, pVersionId As %String = "") As %DynamicObject
{
	return ..PostProcessResource(##super(pResourceType, pResourceId, pVersionId))
}

/// Process resource before return
Method PostProcessResource(resource As %DynamicObject) As %DynamicObject
{
	do ..SetDisplayFor4References(resource)
	do ..AddOrUpdateText(resource)

	return resource
}

/// Add or update Text
Method AddOrUpdateText(resource As %DynamicObject)
{
	if (resource.text = "") || (resource.text.status = "generated")
	{
		try
		{
			set text = $CLASSMETHOD("MyFHIRServer.Resources." _ resource.resourceType, "GenerateText", resource)
			set resource.text = {
				"status": "generated",
				"div": ("<div xmlns=""http://www.w3.org/1999/xhtml""><p><b>Generated</b></p>" _  text _ "</div>")
			}
		}
		catch ex
		{
			$$$FSLog("Failed to get text for " _ resource.resourceType _ "/" _ resource.id _ ": " _ $system.Status.GetErrorText(ex.AsStatus()))
		}
	}
}

/// Set display for references
Method SetDisplayFor4References(resource As %DynamicObject)
{
	set visitContext("schema") = ..strategy.schema
	set visitContext("callbackInstance") = $THIS
	set visitContext("callbackMethod") = "AddDisplayForReference"

	do ##class(HS.FHIRServer.Util.ReferenceVisitor).VisitAll(resource, .visitContext)
}

/// Add display for a single reference
Method AddDisplayForReference(ByRef context, reference As %DynamicObject)
{
	#; set propName = context("_va", "curPropName")
	set resourceType = $PIECE(reference.reference, "/", 1)

	try
	{
		set resourceClass = ..strategy.GetResourceClass(resourceType)
		set reference.display = "(not-found)"

		if $classmethod(resourceClass, "KeyIdxExists", reference.reference) // resource exists?
		{
			set storageObject = $classmethod(resourceClass, "KeyIdxOpen", reference.reference, -1, .tSC)

			if (storageObject.Deleted = 0) // Not deleted
			{
				set reference.display = $CLASSMETHOD("MyFHIRServer.Resources." _ resourceType, "GetDisplayForReference", storageObject.ResourceObject)
			}
		}
	}
	catch ex
	{
		$$$FSLog("Failed to get display for " _ reference.reference _ ": " _ $system.Status.GetErrorText(ex.AsStatus()))
	}
}

/// Check referential integrity before delete
Method Delete(pResourceType As %String, pResourceId As %String) As %String
{
	do ..CheckDelete(pResourceType, pResourceId)

	return ##super(pResourceType, pResourceId)
}

/// Check if the caller is allowed to delete the specified resource
Method CheckDelete(pResourceType As %String, pResourceId As %String) As %Boolean
{
	set exists = ..GetResourceFromDB(pResourceType, pResourceId, , .url, .version)

	if exists
	{
		if (pResourceType = "ActivityDefinition")
		{
			do ##class(MyFHIRServer.Util.ActivityDefinitionHelper).EnsureNoBreakingLinks($THIS, pResourceId, url, version)
		}
		else
		{
			do ##class(MyFHIRServer.Util.RefintReverseHelper).EnsureNoLinksBeforeDelete($THIS, pResourceType, pResourceId)
		}

		$$$FSLog("It is allowed to delete resource " _ $$$BuildRsrcKey(pResourceType, pResourceId) _ "!")
	}

	return exists
}

/// Get the ResourceOrigin from the stored resource using the resource type and id
Method GetResourceFromDB(resourceType As %String, id As %String, Output versionId As %String, Output url As %String, Output version As %String, Output patient As %String) As %Boolean
{
	set versionId = ""
	set url = ""
	set version = ""
	set patient = ""
	set tableName = ..getTableForResourceType(resourceType)
	
	set query = "SELECT VersionId"

	if (resourceType = "ActivityDefinition")
	{
		set query = query _ ", url, version"
	}
	elseif (resourceType = "Task")
	{
		set query = query _ ", patient"
	}

	set query = query _ " FROM "_tableName_" WHERE _id = '" _ id _ "'"

	#dim result As %SQL.StatementResult = ##class(HS.FHIRServer.Util.RunSQLQuery).runQuery(query)

	if result.%Next()
	{
		set versionId = result.%Get("VersionId")

		if (resourceType = "ActivityDefinition")
		{
			set url = result.%Get("url")
			set version = result.%Get("version")
		}
		elseif (resourceType = "Task")
		{
			set patient = result.%Get("patient")
		}

		return 1 // record found
	}
	
	return 0 // record not found
}

}
