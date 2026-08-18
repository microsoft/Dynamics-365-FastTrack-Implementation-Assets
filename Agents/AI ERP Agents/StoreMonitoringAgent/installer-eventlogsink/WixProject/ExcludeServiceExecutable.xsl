<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:wix="http://wixtoolset.org/schemas/v4/wxs">
    <xsl:output method="xml" indent="yes" />
    <xsl:strip-space elements="*" />
    <xsl:key name="excluded-components"
        match="wix:Component[wix:File[substring(@Source, string-length(@Source) - string-length('EventLogSinkConfigService.exe') + 1) = 'EventLogSinkConfigService.exe']]"
        use="@Id" />

    <xsl:template match="@*|node()">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()" />
        </xsl:copy>
    </xsl:template>

    <xsl:template
        match="wix:Component[wix:File[substring(@Source, string-length(@Source) - string-length('EventLogSinkConfigService.exe') + 1) = 'EventLogSinkConfigService.exe']]" />
    <xsl:template match="wix:ComponentRef[key('excluded-components', @Id)]" />
</xsl:stylesheet>