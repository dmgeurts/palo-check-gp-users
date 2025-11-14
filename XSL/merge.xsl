<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="xml" indent="yes"/>

  <!-- Key grouping entries by username -->
  <xsl:key name="by-user" match="entry" use="username"/>

  <xsl:template match="/">
    <records>

      <!-- unique usernames -->
      <xsl:for-each select="//entry[generate-id() = generate-id(key('by-user', username)[1])]">

        <xsl:variable name="uname" select="username"/>
        <xsl:variable name="all" select="key('by-user', $uname)"/>

        <!-- newest entry for this user -->
        <xsl:variable name="latest"
             select="$all[not(number(login-time-utc) &lt; number(../login-time-utc))]" />

        <entry>
          <username><xsl:value-of select="$uname"/></username>

          <!-- choose nonempty, or fallback -->
          <active><xsl:value-of select="$all/active[normalize-space()][1]"/></active>
          <current-count><xsl:value-of select="$all/current-count[normalize-space()][1]"/></current-count>
          <previous-count><xsl:value-of select="$all/previous-count[normalize-space()][1]"/></previous-count>

          <login-time-utc><xsl:value-of select="$latest/login-time-utc"/></login-time-utc>
          <logout-time-utc><xsl:value-of select="$all/logout-time-utc[normalize-space()][1]"/></logout-time-utc>
          <reason><xsl:value-of select="$all/reason[normalize-space()][1]"/></reason>

          <!-- shared keys -->
          <vpn-type><xsl:value-of select="$all/vpn-type[normalize-space()][1]"/></vpn-type>
          <client-ip><xsl:value-of select="$all/client-ip[normalize-space()][1]"/></client-ip>
          <source-region><xsl:value-of select="$all/source-region[normalize-space()][1]"/></source-region>
          <client><xsl:value-of select="$all/client[normalize-space()][1]"/></client>
          <app-version><xsl:value-of select="$all/app-version[normalize-space()][1]"/></app-version>

        </entry>

      </xsl:for-each>
    </records>
  </xsl:template>

</xsl:stylesheet>
