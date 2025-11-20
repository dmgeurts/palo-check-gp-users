<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="xml" indent="yes"/>

  <xsl:key name="cert-lookup" match="entry[not(active)]" use="common-name"/>

  <xsl:template match="/">
    <records>

      <xsl:for-each select="//entry[active]">
        
        <xsl:variable name="uname" select="username"/>
        <xsl:variable name="isActive" select="active"/> <xsl:variable name="login" select="number(login-time-utc)"/>

        <xsl:variable name="logout">
            <xsl:choose>
                <xsl:when test="string(number(logout-time-utc)) != 'NaN'">
                    <xsl:value-of select="number(logout-time-utc)"/>
                </xsl:when>
                <xsl:otherwise>0</xsl:otherwise>
            </xsl:choose>
        </xsl:variable>

        <xsl:variable name="certNode" select="key('cert-lookup', $uname)"/>

        <entry>
            <session_id>
                <xsl:value-of select="client-ip"/>_<xsl:value-of select="login-time-utc"/>
            </session_id>

            <username><xsl:value-of select="$uname"/></username>

            <status>
                <xsl:choose>
                    <xsl:when test="$isActive = 'yes'">active</xsl:when>
                    <xsl:otherwise>disconnected</xsl:otherwise>
                </xsl:choose>
            </status>

            <source_region><xsl:value-of select="source-region"/></source_region>
            <vpn_type><xsl:value-of select="vpn-type"/></vpn_type>
            <tunnel_type><xsl:value-of select="tunnel-type"/></tunnel_type>
            <client_os><xsl:value-of select="client"/></client_os>
            <app_version><xsl:value-of select="app-version"/></app_version>
            <host_id><xsl:value-of select="host-id"/></host_id>
            <client_ip><xsl:value-of select="client-ip"/></client_ip>
            <disconnect_reason><xsl:value-of select="reason"/></disconnect_reason>
            <login_epoch><xsl:value-of select="$login"/></login_epoch>

            <logout_epoch>
                <xsl:choose>
                    <xsl:when test="$isActive = 'yes'">0</xsl:when>
                    <xsl:otherwise><xsl:value-of select="$logout"/></xsl:otherwise>
                </xsl:choose>
            </logout_epoch>

            <xsl:if test="$isActive != 'yes' and $logout > 0">
                <duration_sec>
                     <xsl:value-of select="$logout - $login"/>
                </duration_sec>
            </xsl:if>

            <cert_name>
                <xsl:choose>
                    <xsl:when test="$certNode"><xsl:value-of select="$certNode/cert-name"/></xsl:when>
                    <xsl:otherwise>none</xsl:otherwise>
                </xsl:choose>
            </cert_name>

            <cert_expiry_epoch>
                <xsl:choose>
                    <xsl:when test="$certNode"><xsl:value-of select="$certNode/cert-expiry-epoch"/></xsl:when>
                    <xsl:otherwise>0</xsl:otherwise>
                </xsl:choose>
            </cert_expiry_epoch>

        </entry>
      </xsl:for-each>

    </records>
  </xsl:template>
</xsl:stylesheet>
