<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="xml" indent="yes"/>

  <!-- Key grouping entries by username -->
  <xsl:key name="by-user" match="entry" use="username"/>

  <!-- Root template -->
  <xsl:template match="/">
    <records>
      <!-- Loop over unique usernames -->
      <xsl:for-each select="//entry[generate-id() = generate-id(key('by-user', username)[1])]">

        <!-- Determine the latest entry for this user -->
        <xsl:variable name="uname" select="username"/>

        <!-- Select the entry with the highest logout-time-utc -->
        <xsl:variable name="latest"
          select="key('by-user', $uname)
                  [not(number(logout-time-utc) &lt; number(../logout-time-utc))]" />

        <entry>
          <username><xsl:value-of select="$latest/username"/></username>
          <entry-count><xsl:value-of select="count(key('by-user', $uname))"/></entry-count>
          <login-time-utc><xsl:value-of select="$latest/login-time-utc"/></login-time-utc>
          <logout-time-utc><xsl:value-of select="$latest/logout-time-utc"/></logout-time-utc>
          <reason><xsl:value-of select="$latest/reason"/></reason>
          <vpn-type><xsl:value-of select="$latest/vpn-type"/></vpn-type>
          <client-ip><xsl:value-of select="$latest/client-ip"/></client-ip>
          <source-region><xsl:value-of select="$latest/source-region"/></source-region>
          <client><xsl:value-of select="$latest/client"/></client>
          <app-version><xsl:value-of select="$latest/app-version"/></app-version>
        </entry>

      </xsl:for-each>
    </records>
  </xsl:template>

</xsl:stylesheet>
