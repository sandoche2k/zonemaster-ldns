use Test::More;
use Test::Fatal;
use Devel::Peek;
use MIME::Base64;

BEGIN { use_ok( 'Zonemaster::LDNS' ) }

my $s;
$s = Zonemaster::LDNS->new( '8.8.8.8' ) if $ENV{TEST_WITH_NETWORK};

subtest 'rdf' => sub {
    SKIP: {
        skip 'no network', 1 unless $ENV{TEST_WITH_NETWORK};

        my $p = $s->query( 'iis.se', 'SOA' );
        plan skip_all => 'No response, cannot test' if not $p;

        foreach my $rr ( $p->answer ) {
            is( $rr->rd_count, 7 );
            foreach my $n (0..($rr->rd_count-1)) {
                ok(length($rr->rdf($n)) >= 4);
            }
            like( exception { $rr->rdf(7) }, qr/Trying to fetch nonexistent RDATA at position/, 'died on overflow');
        }
    }
};

subtest 'SOA' => sub {
    SKIP: {
        skip 'no network', 1 unless $ENV{TEST_WITH_NETWORK};

        my $p = $s->query( 'iis.se', 'SOA' );
        plan skip_all => 'No response, cannot test' if not $p;

        foreach my $rr ( $p->answer ) {
            isa_ok( $rr, 'Zonemaster::LDNS::RR::SOA' );
            is( lc($rr->mname), 'ns.nic.se.' );
            is( lc($rr->rname), 'hostmaster.iis.se.' );
            ok( $rr->serial >= 1381471502, 'serial' );
            is( $rr->refresh, 14400,   'refresh' );
            is( $rr->retry,   3600,    'retry' );
            is( $rr->expire,  1814400, 'expire' );
            is( $rr->minimum, 14400,   'minimum' );
        }
    }
};

subtest 'A' => sub {
    SKIP: {
        skip 'no network', 1 unless $ENV{TEST_WITH_NETWORK};

        my $p = $s->query( 'a.ns.se' );
        plan skip_all => 'No response, cannot test' if not $p;

        foreach my $rr ( $p->answer ) {
            isa_ok( $rr, 'Zonemaster::LDNS::RR::A' );
            is( $rr->address, '192.36.144.107', 'expected address string' );
            is( $rr->type, 'A' );
            is( length($rr->rdf(0)), 4 );
        }
    }
};

subtest 'AAAA' => sub {
    SKIP: {
        skip 'no network', 1 unless $ENV{TEST_WITH_NETWORK};

        $p = $s->query( 'a.ns.se', 'AAAA' );
        plan skip_all => 'No response, cannot test' if not $p;

        foreach my $rr ( $p->answer ) {
            isa_ok( $rr, 'Zonemaster::LDNS::RR::AAAA' );
            is( $rr->address, '2a01:3f0:0:301::53', 'expected address string' );
            is( length($rr->rdf(0)), 16 );
        }
    }
};

subtest 'TXT' => sub {
    SKIP: {
        skip 'no network', 1 unless $ENV{TEST_WITH_NETWORK};

        my $se = Zonemaster::LDNS->new( '192.36.144.107' );
        my $pt = $se->query( 'se', 'TXT' );
        plan skip_all => 'No response, cannot test' if not $pt;

        foreach my $rr ( $pt->answer ) {
            isa_ok( $rr, 'Zonemaster::LDNS::RR::TXT' );
            like( $rr->txtdata, qr/^"SE zone update: / );
        }
    }
};

subtest 'DNSKEY' => sub {
    SKIP: {
        skip 'no network', 1 unless $ENV{TEST_WITH_NETWORK};

        my $se = Zonemaster::LDNS->new( '192.36.144.107' );
        my $pk = $se->query( 'se', 'DNSKEY' );
        plan skip_all => 'No response, cannot test' if not $pk;

        foreach my $rr ( $pk->answer ) {
            isa_ok( $rr, 'Zonemaster::LDNS::RR::DNSKEY' );
            ok( $rr->flags == 256 or $rr->flags == 257 );
            is( $rr->protocol,  3 );
            # Alg 8 will replace 5. Now (December 2017) both are used.
            ok( $rr->algorithm == 5 or $rr->algorithm == 8 );
        }
    }
};

subtest 'RRSIG' => sub {
    SKIP: {
        skip 'no network', 1 unless $ENV{TEST_WITH_NETWORK};

        my $se = Zonemaster::LDNS->new( '192.36.144.107' );
        my $pr = $se->query( 'se', 'RRSIG' );
        plan skip_all => 'No response, cannot test' if not $pr;

        foreach my $rr ( $pr->answer ) {
            isa_ok( $rr, 'Zonemaster::LDNS::RR::RRSIG' );
            is( $rr->signer, 'se.' );
            is( $rr->labels, 1 );
            if ( $rr->typecovered eq 'DNSKEY' ) {
                # .SE KSK should not change very often. 59407 will replace 59747.
                # Now (December 2017) both are used.
                ok( $rr->keytag == 59747 or $rr->keytag == 59407 );
            }
        }
    }
};

subtest 'NSEC' => sub {
    SKIP: {
        skip 'no network', 1 unless $ENV{TEST_WITH_NETWORK};

        my $se = Zonemaster::LDNS->new( '192.36.144.107' );
        my $pn = $se->query( 'se', 'NSEC' );
        plan skip_all => 'No response, cannot test' if not $pn;

        foreach my $rr ( $pn->answer ) {
            isa_ok( $rr, 'Zonemaster::LDNS::RR::NSEC' );
            ok( $rr->typehref->{TXT} );
            ok( !$rr->typehref->{MX} );
            ok( $rr->typehref->{TXT} );
            is( $rr->typelist, 'NS SOA TXT RRSIG NSEC DNSKEY ' );
        }
    }
};

subtest 'From string' => sub {
    my $made = Zonemaster::LDNS::RR->new_from_string( 'nic.se IN NS a.ns.se' );
    isa_ok( $made, 'Zonemaster::LDNS::RR::NS' );
    my $made2 = Zonemaster::LDNS::RR->new_from_string( 'nic.se IN NS a.ns.se' );
    is( $made->compare( $made2 ), 0, 'direct comparison works' );
    my $made3 = Zonemaster::LDNS::RR->new_from_string( 'mic.se IN NS a.ns.se' );
    my $made4 = Zonemaster::LDNS::RR->new_from_string( 'oic.se IN NS a.ns.se' );
    is( $made->compare( $made3 ), 1,  'direct comparison works' );
    is( $made->compare( $made4 ), -1, 'direct comparison works' );
    is( $made eq $made2,          1,  'indirect comparison works' );
    is( $made <=> $made3,         1,  'indirect comparison works' );
    is( $made cmp $made4,         -1, 'indirect comparison works' );

    is( "$made", "nic.se.	3600	IN	NS	a.ns.se." );
};

subtest 'DS' => sub {
    SKIP: {
        skip 'no network', 1 unless $ENV{TEST_WITH_NETWORK};

        my $se      = Zonemaster::LDNS->new( '192.36.144.107' );
        my $pd      = $se->query( 'nic.se', 'DS' );
        plan skip_all => 'No response, cannot test' if not $pd;

        my $nic_key = Zonemaster::LDNS::RR->new(
    'nic.se IN DNSKEY 257 3 5 AwEAAdhJAx197qFpGGXuQn8XH0tQpQSfjvLKMcreRvJyO+f3F3weIHR3 6E8DObolHFp+m1YkxsgnHYjUFN4E9sKa38ZXU0oHTSsB3adExJkINA/t INDlKrzUDn4cIbyUCqHNGe0et+lHmjmfZdj62GJlHgVmxizYkoBd7Rg0 wxzEOo7CA3ZadaHuqmVJ2HvqRCoe+5NDsYpnDia7WggvLTe0vorV6kDc u6d5N9AUPwBsR7YUkbetfXMtUebux71kHCGUJdmzp84MeDi9wXYIssjR oTC5wUF2H3I2Mnj5GqdyBwQCdj5otFbRAx3jiMD+ROxXJxOFdFq7fWi1 yPqUf1jpJ+8='
        );
        my $made = Zonemaster::LDNS::RR->new_from_string( 'nic.se IN NS a.ns.se' );
        foreach my $rr ( $pd->answer ) {
            isa_ok( $rr, 'Zonemaster::LDNS::RR::DS' );
            is( $rr->keytag,    16696 );
            is( $rr->algorithm, 5 );
            ok( $rr->digtype == 1 or $rr->digtype == 2 );
            ok(
                     $rr->hexdigest eq '40079ddf8d09e7f10bb248a69b6630478a28ef969dde399f95bc3b39f8cbacd7'
                  or $rr->hexdigest eq 'ef5d421412a5eaf1230071affd4f585e3b2b1a60'
            );
            ok( $rr->verify( $nic_key ), 'derived from expected DNSKEY' );
            ok( !$rr->verify( $made ),   'does not match a non-DS non-DNSKEY record' );
        }
    }
};

subtest 'NSEC3' => sub {
    my $nsec3 = Zonemaster::LDNS::RR->new_from_string(
        'VD0J8N54V788IUBJL9CN5MUD416BS5I6.com. 86400 IN NSEC3 1 1 0 - VD0N3HDL5MG940MOUBCF5MNLKGDT9RFT NS DS RRSIG' );
    isa_ok( $nsec3, 'Zonemaster::LDNS::RR::NSEC3' );
    is( $nsec3->algorithm, 1 );
    is( $nsec3->flags,     1 );
    ok( $nsec3->optout );
    is( $nsec3->iterations,                  0 );
    is( $nsec3->salt,                        undef );
    is( encode_base64( $nsec3->next_owner ), "FPtBccW1LaCSAtjy2PLa9aQb1O39\n" );
    is( $nsec3->typelist,                    'NS DS RRSIG ' );

    is_deeply( [ sort keys %{ $nsec3->typehref } ], [qw(DS NS RRSIG)] );
};

subtest 'NSEC3PARAM' => sub {
    my $nsec3param = Zonemaster::LDNS::RR->new_from_string( 'whitehouse.gov.		3600	IN	NSEC3PARAM 1 0 1 B2C19AB526819347' );
    isa_ok( $nsec3param, 'Zonemaster::LDNS::RR::NSEC3PARAM' );
    is( $nsec3param->algorithm,  1 );
    is( $nsec3param->flags,      0 );
    is( $nsec3param->iterations, 1, "Iterations" );
    is( encode_base64( $nsec3param->salt ), "CLLBmrUmgZNH\n", "Salt" );
    is( lc($nsec3param->owner), 'whitehouse.gov.' );
};

subtest 'SRV' => sub {
    my $srv = Zonemaster::LDNS::RR->new( '_nicname._tcp.se.	172800	IN	SRV	0 0 43 whois.nic-se.se.' );
    is( $srv->type, 'SRV' );
};

subtest 'SPF' => sub {
    my $spf = Zonemaster::LDNS::RR->new(
        'frobbit.se.		1127	IN	SPF	"v=spf1 ip4:85.30.129.185/24 mx:mail.frobbit.se ip6:2a02:80:3ffe::0/64 ~all"' );
    isa_ok( $spf, 'Zonemaster::LDNS::RR::SPF' );
    is( $spf->spfdata, '"v=spf1 ip4:85.30.129.185/24 mx:mail.frobbit.se ip6:2a02:80:3ffe::0/64 ~all"' );
};

done_testing;
