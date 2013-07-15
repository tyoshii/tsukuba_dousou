#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

use Config::Tiny;
use Data::Dumper;
use Encode;
use Furl;
use HTML::TreeBuilder;
use Net::Twitter;
use WWW::Shorten qw( TinyURL :short );
use XML::Simple;

use constant CACHE_FILE => $ENV{HOME}.'/bin/tsukuba_dousou/cache';

use constant {
    ACCESS_TOKEN        => '241532256-gv3SNGeRITxQTh4rSj3kbfnDaQHEf16PtE9PrcQ',
    ACCESS_TOKEN_SECRET => 'zlF83MgHnyqeNGos36ZJeniLOqwdp72cOBzVh31DrY',
    CONSUMER_KEY        => 'xtNlWWJyjXuZoQkBPJUaw',
    CONSUMER_SECRET     => 'FtcLJe9IhnPr50ZmMfNf5ZeAlvjzTHKfXLMVYeXd90',
};

use constant {
    UNIV_BLOG_RSS   => 'http://blog.goo.ne.jp/tsukuba_baseball/index.rdf',
    DOUSOU_BLOG_RSS => 'http://feedblog.ameba.jp/rss/ameblo/tsukuba-dousoukai',
    LEAGUE_NEWS     => 'http://www.hino.meisei-u.ac.jp/SBBL/sbbl/news_dsp1.php',
    TOPICS          => 'http://club.taiiku.tsukuba.ac.jp/baseball/archives/topics/',
};

sub fatal {
    my $msg = shift;
    _log( 'FATAL', $msg );
    
    Carp::croak $msg;
}

sub _log {
    my $status = shift;
    my $msg    = shift;

    print sprintf "%s [%s] %s\n"
        , scalar localtime 
        , $status
        , encode( 'utf8', $msg )
        ;
}

sub info {
    my $msg = shift;
    _log( 'INFO', $msg );
}


sub main {
    my $new_items = get_new_items();

    if ( @$new_items == 0 ) {
        # info('Not update items');
        exit 0;
    }

    tweet( $new_items );
}


sub get_new_items {

    my $furl = Furl->new( timeout => 10 );
    my $conf = Config::Tiny->read( CACHE_FILE );
    
    my  %items = (
        univ   => _check_rss(       $furl->get( UNIV_BLOG_RSS ),   $conf->{'_'}->{'univ'}   ),
        dousou => _check_rss(       $furl->get( DOUSOU_BLOG_RSS ), $conf->{'_'}->{'dousou'} ),
        league => _get_league_news( $furl->get( LEAGUE_NEWS ),     $conf->{'_'}->{'league'} ),
        topics => _get_topics(      $furl->get( TOPICS ),          $conf->{'_'}->{'topics'} ),
    );


=test
    my $univ_items
        = _check_rss( $furl->get( UNIV_BLOG_RSS ), $conf->{'_'}->{'univ'} );
    my $dousou_items
        = _check_rss( $furl->get( DOUSOU_BLOG_RSS ), $conf->{'_'}->{'dousou'} );
    my $league_items 
        = _get_league_news( $furl->get( LEAGUE_NEWS ), $conf->{'_'}->{'league'} );  
    my $topics
        = _get_topics( $furl->get( TOPICS ), $conf->{'_'}->{'topics'} );
=cut

    my @return;
    for my $key ( keys %items ) {
        if ( exists $items{$key}->{'cache'} ) {
            $conf->{'_'}->{$key} = $items{$key}->{'cache'};

            for ( @{ $items{$key}->{'entry'} } ) {
                push @return, sprintf('%s - %s %s', $items{$key}->{'title'}, $_->{'title'}, $_->{'link'} );
            }
        }
    }

=test
    my @return;
    if ( exists $univ_items->{'cache'} ) {
        $conf->{'_'}->{'univ'} = $univ_items->{'cache'};
    
        for ( @{ $univ_items->{'entry'} } ) {
            push @return, sprintf('%s - %s %s', $univ_items->{'title'}, $_->{'title'}, $_->{'link'} );
        }
    }

    if ( exists $dousou_items->{'cache'} ) {
        $conf->{'_'}->{'dousou'} = $dousou_items->{'cache'};

        for ( @{ $dousou_items->{'entry'} } ) {
            push @return, sprintf('%s - %s %s', $dousou_items->{'title'}, $_->{'title'}, $_->{'link'} );
        }
    }

    if ( exists $league_items->{'cache'} ) {
        $conf->{'_'}->{'league'} = $league_items->{'cache'};

        for ( @{ $league_items->{'entry'} } ) {
            push @return, sprintf('%s - %s %s', $league_items->{'title'}, $_->{'title'}, $_->{'link'} );
        }
    }

    if ( exists $topics->{'cache'} ) {
        $conf->{'_'}->{'topics'} = $topics->{'cache'};

        for ( @{ $topics->{'entry'} } ) {
            push @return, sprintf('%s - %s %s', $topics->{'title'}, $_->{'title'}, $_->{'link'} );
        }
    }
=cut

    $conf->write( CACHE_FILE );

    return \@return;
}

sub _get_topics {
    my $res = shift;
    my $cache = shift;

    if (! $res->is_success() ) {
        fatal('Failed get homepage topics feed');
    }

    my $tree = HTML::TreeBuilder->new()->parse( decode( 'utf8', $res->content() ) );

    my @topics = $tree->look_down('id', 'box1')->look_down('class', 'archive_list');

    my $return = {
        title => '野球部ホームページ',
        entry => [],
    };

    for my $topic ( @topics ) {
        my $text = $topic->as_text();
        $text =~ s{\s|　}{}g;
        $text =~ m{^(.*?)\((.*?)\)$};

        my $title = $1;
        my $date  = $2;

        $date =~ m{(\d{4})年(\d{1,2})月(\d{1,2})日};
        my $year  = $1;
        my $month = $2;
        my $day   = $3;

        $month = '0'.$month if $month < 10;
        $day   = '0'.$day   if $day   < 10;
        
        $date = "$year$month$day";
    
        last if $cache ne '' && $cache >= $date;
        
        #_save latest date
        $return->{'cache'} = $date
            if ! exists $return->{'cache'} || int($return->{'cache'}) < int($date);
    
        my $link = short_link( $topic->find('a')->{'href'} );
        
        push @{ $return->{'entry'} }, {
            title => $title,
            link  => $link,
        };
    }

    return $return;
}

sub _get_league_news {
    my $res   = shift;
    my $cache = shift;

    if (! $res->is_success() ) {
        fatal('Failed get league news feed');
    }

    my $tree = HTML::TreeBuilder->new()->parse( $res->content() ); 

    my @news = $tree->find('font');

    my $return = {
        title => '首都大学野球連盟',
        entry => [],
    };

    while ( scalar @news ) {
        my $date = shift @news;
        my $item = shift @news;

        $date->as_text() =~ m{^\[(\d{2})/(\d{2})\]$};
        $date = "$1$2";

        last if $cache ne '' && $cache == $date;

        #_save latest date
        $return->{'cache'} = $date
            if ! exists $return->{'cache'} || int($return->{'cache'}) < int($date);

        my $link = short_link( "http://www.hino.meisei-u.ac.jp/SBBL/sbbl/".$item->find('a')->{'href'} );

        push @{ $return->{'entry'} }, {
            title => decode( 'shiftjis', $item->as_text() ),
            link  => $link,
        };
    }

    return $return;
}

sub _check_rss {
    my $res   = shift;
    my $cache = shift;

    if (! $res->is_success() ) {
        fatal('Failed get univ blog rss feed');
    }
    
    my $data = XMLin( $res->content() );

    my $return = {
        title => $data->{'channel'}->{'title'},
        entry => [],
    };

    for my $item ( @{ $data->{'item'} } ) {

        #_get date
        $item->{'dc:date'} =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/;  
        my $date = "$1$2$3$4$5$6";

        #_is update?
        last if $cache ne '' && $cache >= $date;

        #_save latest date
        $return->{'cache'} = $date
            if ! exists $return->{'cache'} || int($return->{'cache'}) < int($date);

        push @{ $return->{'entry'} }, {
            title => $item->{'title'}, 
            link  => short_link( $item->{'link'} ),
        };
    }

    return $return;
}

sub tweet {

    my $new_items = shift;

    my $t = Net::Twitter->new(
        traits   => [qw/OAuth API::REST/],
        access_token => ACCESS_TOKEN,
        access_token_secret => ACCESS_TOKEN_SECRET,
        consumer_key => CONSUMER_KEY,
        consumer_secret => CONSUMER_SECRET,
    );

    for ( @$new_items ) {
        info("tweet $_");
        $t->update( $_ );
    }
}

main();
