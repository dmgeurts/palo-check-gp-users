<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="xml" indent="yes"/>

  <!-- Group all entries by username -->
  <xsl:key name="by-user" match="entry" use="username"/>

  <xsl:template match="/">
    <records>

      <!-- For each unique username -->
      <xsl:for-each select="//entry[generate-id() = generate-id(key('by-user', username)[1])]">

        <xsl:variable name="uname" select="username"/>
        <xsl:variable name="userEntries" select="key('by-user', $uname)"/>

        <!-- SESSION entries (those having login-time-utc) -->
        <xsl:variable name="sessionEntries" select="$userEntries[login-time-utc]"/>

        <!-- LATEST session login -->
        <xsl:variable name="latestLogin" select="$sessionEntries[not(number(login-time-utc) &lt; number(../login-time-utc))]"/>

        <!-- LATEST session logout -->
        <xsl:variable name="latestLogout" select="$sessionEntries[ not(number(logout-time-utc) &lt; number(../logout-time-utc))]"/>

        <!-- ACTIVE: active=yes only if ANY session entry says active=yes -->
        <xsl:variable name="active">
          <xsl:choose>
            <xsl:when test="$sessionEntries[active='yes']">yes</xsl:when>
            <xsl:otherwise>no</xsl:otherwise>
          </xsl:choose>
        </xsl:variable>

        <!-- COUNTS (certificate-only entries excluded) -->
        <xsl:variable name="currentCount" select="count($sessionEntries[not(normalize-space(logout-time-utc))])"/>

        <xsl:variable name="previousCount" select="count($sessionEntries[normalize-space(logout-time-utc)])"/>

        <!-- CERT METADATA (may be none, may be multiple) -->
        <xsl:variable name="certName" select="$userEntries/cert-name"/>
        <xsl:variable name="certExpiry" select="$userEntries/cert-expiry-epoch"/>

        <entry>
          <username><xsl:value-of select="$uname"/></username>

          <active><xsl:value-of select="$active"/></active>

          <!-- EMPTY IF ZERO -->
          <current-count>
            <!-- <xsl:if test="$currentCount &gt; 0"> -->
              <xsl:value-of select="$currentCount"/>
            <!-- </xsl:if> -->
          </current-count>

          <previous-count>
            <!-- <xsl:if test="$previousCount &gt; 0"> -->
              <xsl:value-of select="$previousCount"/>
            <!-- </xsl:if> -->
          </previous-count>

          <!-- LOGIN / LOGOUT FIELDS ONLY FOR SESSION ENTRIES -->
          <login-time-utc>
            <xsl:value-of select="$latestLogin/login-time-utc"/>
          </login-time-utc>

          <logout-time-utc>
            <xsl:value-of select="$latestLogout/logout-time-utc"/>
          </logout-time-utc>

          <reason>
            <xsl:value-of select="$latestLogout/reason"/>
          </reason>

          <!-- SESSION FIELDS (latest session only) -->
          <vpn-type>
            <xsl:value-of select="$latestLogin/vpn-type"/>
          </vpn-type>

          <client-ip>
            <xsl:value-of select="$latestLogin/client-ip"/>
          </client-ip>

          <source-region>
            <xsl:value-of select="$latestLogin/source-region"/>
          </source-region>

          <client>
            <xsl:value-of select="$latestLogin/client"/>
          </client>

          <app-version>
            <xsl:value-of select="$latestLogin/app-version"/>
          </app-version>

          <!-- CERTIFICATE FIELDS -->
          <cert-name>
            <xsl:value-of select="$certName"/>
          </cert-name>

          <cert-expiry-epoch>
            <xsl:value-of select="$certExpiry"/>
          </cert-expiry-epoch>

        </entry>

      </xsl:for-each>

    </records>
  </xsl:template>

</xsl:stylesheet>
