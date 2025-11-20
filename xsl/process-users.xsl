<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="xml" indent="yes"/>

  <xsl:key name="cert-lookup" match="entry[not(active)]" use="common-name"/>
  <xsl:key name="vpn-lookup" match="entry[active]" use="username"/>

  <xsl:template match="/">
    <records>

      <xsl:for-each select="//entry[active]">

        <xsl:variable name="uname" select="username"/>
        <xsl:variable name="isActive" select="active"/>
        <xsl:variable name="login" select="number(login-time-utc)"/>

        <xsl:variable name="logout">
          <xsl:if test="string(number(logout-time-utc)) != 'NaN'">
            <xsl:value-of select="number(logout-time-utc)"/>
          </xsl:if>
        </xsl:variable>

        <xsl:variable name="certNode" select="key('cert-lookup', $uname)"/>

        <entry>
          <session_id><xsl:value-of select="client-ip"/>_<xsl:value-of select="login-time-utc"/></session_id>
          <username><xsl:value-of select="$uname"/></username>

          <status>
            <xsl:choose>
              <xsl:when test="$isActive = 'yes'">active</xsl:when>
              <xsl:otherwise>disconnected</xsl:otherwise>
            </xsl:choose>
          </status>

          <source_region><xsl:value-of select="source-region"/></source_region>
          <vpn_type><xsl:value-of select="vpn-type"/></vpn-type>
          <tunnel_type><xsl:value-of select="tunnel-type"/></tunnel_type>
          <client_os><xsl:value-of select="client"/></client_os>
          <app_version><xsl:value-of select="app-version"/></app_version>
          <host_id><xsl:value-of select="host-id"/></host_id>

          <login_epoch><xsl:value-of select="$login"/></login_epoch>

          <logout_epoch><xsl:value-of select="$logout"/></logout_epoch>

          <xsl:if test="$isActive != 'yes' and string-length($logout) > 0">
            <duration_sec><xsl:value-of select="$logout - $login"/></duration_sec>
          </xsl:if>

          <client_ip><xsl:value-of select="client-ip"/></client_ip>
          <disconnect_reason><xsl:value-of select="reason"/></disconnect_reason>

          <cert_name>
            <xsl:if test="$certNode">
              <xsl:value-of select="$certNode/cert-name"/>
            </xsl:if>
          </cert_name>

          <cert_expiry_epoch>
            <xsl:if test="$certNode">
              <xsl:value-of select="$certNode/cert-expiry-epoch"/>
            </xsl:if>
          </cert_expiry_epoch>
        </entry>
      </xsl:for-each>

      <xsl:for-each select="//entry[not(active)]">
        <xsl:variable name="certUser" select="common-name"/>

        <xsl:if test="not(key('vpn-lookup', $certUser))">
          <entry>
            <session_id>cert_only_<xsl:value-of select="$certUser"/></session_id>
            <username><xsl:value-of select="$certUser"/></username>
            <status>unused</status>

            <source_region></source_region>
            <vpn_type></vpn_type>
            <tunnel_type></tunnel_type>
            <client_os></client_os>
            <app_version></app_version>
            <host_id></host_id>

            <login_epoch></login_epoch>
            <logout_epoch></logout_epoch>
            <client_ip></client_ip>

            <disconnect_reason>Certificate exists but no session data</disconnect_reason>

            <cert_name><xsl:value-of select="cert-name"/></cert_name>
            <cert_expiry_epoch><xsl:value-of select="cert-expiry-epoch"/></cert_expiry-epoch>
          </entry>
        </xsl:if>
      </xsl:for-each>

    </records>
  </xsl:template>
</xsl:stylesheet>
