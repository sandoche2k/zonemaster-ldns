#include <string.h>
#include <stdlib.h>
#include <ldns/ldns.h>
#include "ldns_glue.h"

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/*
 *  NetLDNS functions
 */

NetLDNS new(char *class, char *str) {
    NetLDNS obj = malloc(sizeof(resolver_t));
    ldns_rdf *ns;
    ldns_status s;

    ns = ldns_rdf_new_frm_str(LDNS_RDF_TYPE_A, str);
    obj->res = ldns_resolver_new();
    s = ldns_resolver_push_nameserver(obj->res, ns);
    if( s != LDNS_STATUS_OK)
    {
        croak("Some sort of error");
    }

    return obj;
}

NetLDNS__Packet mxquery(NetLDNS obj, char *dname) {
    ldns_rdf *domain;
    NetLDNS__Packet p;

    domain = ldns_dname_new_frm_str(dname);
    p = ldns_resolver_query(obj->res, domain, LDNS_RR_TYPE_MX, LDNS_RR_CLASS_IN, LDNS_RD);

    return p;
}

NetLDNS__Packet query(NetLDNS obj, char *dname, char *rrtype, char *rrclass) {
    ldns_rdf *domain;
    ldns_rr_type t;
    ldns_rr_class c;
    NetLDNS__Packet p;

    t = ldns_get_rr_type_by_name(rrtype);
    if(!t)
    {
        croak("Unknown RR type");
    }

    c = ldns_get_rr_class_by_name(rrclass);
    if(!c)
    {
        croak("Unknown RR class");
    }

    domain = ldns_dname_new_frm_str(dname);
    p = ldns_resolver_query(obj->res, domain, t, c, LDNS_RD);

    return p;
}

void DESTROY(NetLDNS obj) {
    ldns_resolver_deep_free(obj->res);
    free(obj);
}

/*
 *  NetLDNS::Packet functions
 */

char *packet_rcode(NetLDNS__Packet obj){
    ldns_buffer *tmp = ldns_buffer_new(0);
    ldns_pkt_rcode2buffer_str(tmp, ldns_pkt_get_rcode(obj));

    return ldns_buffer_export(tmp);    
}

void packet_DESTROY(NetLDNS__Packet obj) {
    ldns_pkt_free(obj);
}