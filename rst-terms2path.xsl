<?xml version="1.0" ?>
<!-- from docutuil-ext.mpe -->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"><xsl:template match="/"><xsl:apply-templates select="//document/definition_list" /></xsl:template><xsl:template match="*/definition_list"><xsl:apply-templates select="definition_list_item" /></xsl:template><xsl:template match="*/definition_list_item">/<xsl:value-of select="term"/><xsl:apply-templates select="definition/definition_list" />/..</xsl:template></xsl:stylesheet>

