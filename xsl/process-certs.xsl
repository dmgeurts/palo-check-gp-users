<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:output method="xml" indent="yes" omit-xml-declaration="yes"/>

  <xsl:template match="/">
      <xsl:for-each select="/response/result/entry">
        <entry>
          <username><xsl:value-of select="common-name"/></username>

          <cert-name><xsl:value-of select="@name"/></cert-name>
          <cert-expiry-epoch><xsl:value-of select="expiry-epoch"/></cert-expiry-epoch>
        </entry>
      </xsl:for-each>
  </xsl:template>
</xsl:stylesheet>
