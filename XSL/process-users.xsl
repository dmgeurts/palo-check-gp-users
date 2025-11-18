ch<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="xml" indent="yes"/>

  <xsl:key name="by-user" match="entry" use="username"/>

  <xsl:template match="/">
    <records>

      <xsl:for-each select="//entry[generate-id() = generate-id(key('by-user', username)[1])]">

        <xsl:variable name="uname" select="username"/>
        <xsl:variable name="userEntries" select="key('by-user', $uname)"/>

        <!-- Most recent login -->
        <xsl:variable name="latest"
          select="$userEntries
                 [not(number(login-time-utc) &lt; number(../login-time-utc))]" />

        <!-- Most recent logout -->
        <xsl:variable name="latestLogout"
          select="$userEntries
                 [not(number(logout-time-utc) &lt; number(../logout-time-utc))]" />

        <!-- ACTIVE logic based on existing active field -->
        <xsl:variable name="active">
          <xsl:choose>
            <xsl:when test="$userEntries[active = 'yes']">yes</xsl:when>
            <xsl:otherwise>no</xsl:otherwise>
          </xsl:choose>
        </xsl:variable>

        <!-- COUNTS -->
        <xsl:variable name="currentCount"
          select="count($userEntries[not(normalize-space(logout-time-utc))])"/>

        <xsl:variable name="previousCount"
          select="count($userEntries[normalize-space(logout-time-utc)])"/>

        <entry>
          <username><xsl:value-of select="$uname"/></username>

          <active><xsl:value-of select="$active"/></active>

          <!-- EMPTY IF ZERO -->
          <current-count>
            <xsl:if test="$currentCount &gt; 0">
              <xsl:value-of select="$currentCount"/>
            </xsl:if>
          </current-count>

          <previous-count>
            <xsl:if test="$previousCount &gt; 0">
              <xsl:value-of select="$previousCount"/>
            </xsl:if>
          </previous-count>

          <login-time-utc>
            <xsl:value-of select="$latest/login-time-utc"/>
          </login-time-utc>

          <logout-time-utc>
            <xsl:value-of select="$latestLogout/logout-time-utc"/>
          </logout-time-utc>

          <reason>
            <xsl:value-of select="$latestLogout/reason"/>
          </reason>

          <vpn-type>
            <xsl:value-of select="$latest/vpn-type[normalize-space()]"/>
          </vpn-type>

          <client-ip>
            <xsl:value-of select="$latest/client-ip[normalize-space()]"/>
          </client-ip>

          <source-region>
            <xsl:value-of select="$latest/source-region[normalize-space()]"/>
          </source-region>

          <client>
            <xsl:value-of select="$latest/client[normalize-space()]"/>
          </client>

          <app-version>
            <xsl:value-of select="$latest/app-version"/>
          </app-version>

          <cert-name>
            <xsl:value-of select="$userEntries/cert-name"/>
          </cert-name>

          <cert-expiry-epoch>
            <xsl:value-of select="$userEntries/cert-expiry-epoch"/>
          </cert-expiry-epoch>

        </entry>

      </xsl:for-each>
    </records>
  </xsl:template>

</xsl:stylesheet>
