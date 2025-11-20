<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="xml" indent="yes"/>

  <!-- Group all entries by username -->
  <xsl:key name="by-user" match="entry" use="username"/>

  <xsl:template match="/">
    <records>

      <!-- Loop over unique usernames -->
      <xsl:for-each select="//entry[generate-id() = generate-id(key('by-user', username)[1])]">

        <xsl:variable name="uname"       select="username"/>
        <xsl:variable name="userEntries" select="key('by-user', $uname)"/>

        <!-- Certificate metadata -->
        <xsl:variable name="certName"   select="$userEntries/cert-name"/>
        <xsl:variable name="certExpiry" select="$userEntries/cert-expiry-epoch"/>

        <!-- All entries containing VPN session data -->
        <xsl:variable name="sessionEntries" select="$userEntries[login-time-utc]"/>

        <!-- Detect certificate-only user -->
        <xsl:variable name="isCertOnly" select="not($sessionEntries) and $certName"/>

        <!-- Detect real session user -->
        <xsl:variable name="isSessionUser" select="boolean($sessionEntries)"/>

        <!-- Latest Session Records -->
        <xsl:variable name="latestLogin"  select="$sessionEntries [not(number(login-time-utc) &lt; number(../login-time-utc))]"/>
        <xsl:variable name="latestLogout" select="$sessionEntries [not(number(logout-time-utc) &lt; number(../logout-time-utc))]"/>

        <!-- ACTIVE state -->
        <xsl:variable name="active">
          <xsl:choose>
            <xsl:when test="$isCertOnly">cn</xsl:when>
            <xsl:when test="$sessionEntries[active='yes']">yes</xsl:when>
            <xsl:otherwise>no</xsl:otherwise>
          </xsl:choose>
        </xsl:variable>

        <!-- COUNTS (session users only) -->
        <xsl:variable name="currentCount"  select="count($sessionEntries[not(normalize-space(logout-time-utc))])"/>
        <xsl:variable name="previousCount" select="count($sessionEntries[normalize-space(logout-time-utc)])"/>

        <!-- OUTPUT BLOCK -->
        <entry>

          <!-- Core -->
          <username><xsl:value-of select="$uname"/></username>
          <active><xsl:value-of select="$active"/></active>

          <!-- Helpers -->
          <is-session-user><xsl:value-of select="$isSessionUser"/></is-session-user>
          <is-cert-only><xsl:value-of select="$isCertOnly"/></is-cert-only>

          <!-- Counters -->
          <current-count>
            <xsl:if test="not($isCertOnly)">
              <xsl:value-of select="$currentCount"/>
            </xsl:if>
          </current-count>

          <previous-count>
            <xsl:if test="not($isCertOnly)">
              <xsl:value-of select="$previousCount"/>
            </xsl:if>
          </previous-count>

          <!-- Session-only fields -->
          <login-time-utc>
            <xsl:if test="$isSessionUser">
              <xsl:value-of select="$latestLogin/login-time-utc"/>
            </xsl:if>
          </login-time-utc>

          <logout-time-utc>
            <xsl:if test="$isSessionUser">
              <xsl:value-of select="$latestLogout/logout-time-utc"/>
            </xsl:if>
          </logout-time-utc>

          <reason>
            <xsl:if test="$isSessionUser">
              <xsl:value-of select="$latestLogout/reason"/>
            </xsl:if>
          </reason>

          <tunnel-type>
            <xsl:if test="$isSessionUser">
              <xsl:value-of select="$latestLogin/tunnel-type"/>
            </xsl:if>
          </tunnel-type>

          <vpn-type>
            <xsl:if test="$isSessionUser">
              <xsl:value-of select="$latestLogin/vpn-type"/>
            </xsl:if>
          </vpn-type>

          <client-ip>
            <xsl:if test="$isSessionUser">
              <xsl:value-of select="$latestLogin/client-ip"/>
            </xsl:if>
          </client-ip>

          <source-region>
            <xsl:if test="$isSessionUser">
              <xsl:value-of select="$latestLogin/source-region"/>
            </xsl:if>
          </source-region>

          <client>
            <xsl:if test="$isSessionUser">
              <xsl:value-of select="$latestLogin/client"/>
            </xsl:if>
          </client>

          <app-version>
            <xsl:if test="$isSessionUser">
              <xsl:value-of select="$latestLogin/app-version"/>
            </xsl:if>
          </app-version>

          <!-- Certificates always output -->
          <cert-name><xsl:value-of select="$certName"/></cert-name>
          <cert-expiry-epoch><xsl:value-of select="$certExpiry"/></cert-expiry-epoch>

        </entry>

      </xsl:for-each>

    </records>
  </xsl:template>

</xsl:stylesheet>
