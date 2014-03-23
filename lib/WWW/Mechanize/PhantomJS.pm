package WWW::Mechanize::PhantomJS;
use strict;
use Selenium::Remote::Driver;
use WWW::Mechanize::Plugin::Selector;
use HTTP::Response;
use HTTP::Headers;
use Scalar::Util qw( blessed );
use File::Basename;
use Carp qw(croak carp);
use WWW::Mechanize::Link;

use vars qw($VERSION %link_spec);
$VERSION= '0.01';

=head1 NAME

WWW::Mechanize::PhantomJS - automate a Selenium PhantomJS capable browser

=cut

=head2 C<< $api->element_query( \@elements, \%attributes ) >>

    my $query = $element_query(['input', 'select', 'textarea'],
                               { name => 'foo' });

Returns the XPath query that searches for all elements with C<tagName>s
in C<@elements> having the attributes C<%attributes>. The C<@elements>
will form an C<or> condition, while the attributes will form an C<and>
condition.

=cut

sub element_query {
    my ($self, $elements, $attributes) = @_;
        my $query =
            './/*[(' .
                join( ' or ',
                    map {
                        sprintf qq{local-name(.)="%s"}, lc $_
                    } @$elements
                )
            . ') and '
            . join( " and ",
                map { sprintf q{@%s="%s"}, $_, $attributes->{$_} }
                  sort keys(%$attributes)
            )
            . ']';
};

sub new {
    my ($class, %options) = @_;

    $options{ port } ||= 4446;

    if (! exists $options{ autodie }) { $options{ autodie } = 1 };

    if( ! exists $options{ frames }) {
        $options{ frames }= 1;
    };

    # Launch PhantomJs
    $options{ launch_exe } ||= 'phantomjs';
    $options{ launch_arg } ||= [ "--PhantomJS=$options{ port }",
                               ];
    my $cmd= "| $options{ launch_exe } @{ $options{ launch_arg } }";
    $options{ pid } ||= open my $fh, $cmd
        or die "Couldn't launch [$cmd]: $! / $?";
    $options{ fh } = $fh;

    # Connect to it
    $options{ driver } ||= Selenium::Remote::Driver->new(
        'port' => $options{ port },
        auto_close => 1,
     );

     my $self= bless \%options => $class;
     
     $self->eval_in_phantomjs(<<'JS');
         var page= this;
         page.errors= [];
         page.onError= function(msg, trace) {
             //_log.warn("Caught JS error", msg);
             page.errors.push({ "message": msg, "trace": trace });
         };
JS
     
     $self
};

sub driver {
    $_[0]->{driver}
};

sub autodie {
    my( $self, $val )= @_;
    $self->{autodie} = $val
        if @_ == 2;
    $_[0]->{autodie}
}

sub allow {
    my($self,%options)= @_;
    for my $opt (keys %options) {
        if( 'javascript' eq $opt ) {
            $self->eval_in_phantomjs(<<'JS', $options{ $opt });
                this.settings.javascriptEnabled= arguments[0]
JS
        } else {
            warn "->allow('$opt', ...) is currently a dummy.";
        };
    };
}

=head2 C<< $mech->js_errors() >>

  print $_->{message}
      for $mech->js_errors();

An interface to the Javascript Error Console

Returns the list of errors in the JEC

Maybe this should be called C<js_messages> or
C<js_console_messages> instead.

=cut

sub js_errors {
    my ($self) = @_;
    my $errors= $self->eval_in_phantomjs(<<'JS');
        return this.errors
JS
    @$errors
}

=head2 C<< $mech->clear_js_errors() >>

    $mech->clear_js_errors();

Clears all Javascript messages from the console

=cut

sub clear_js_errors {
    my ($self) = @_;
    my $errors= $self->eval_in_phantomjs(<<'JS');
        this.errors= [];
JS

};

sub document {
    $_[0]->driver->find_element('html','tag_name');
}

=head2 C<< $mech->eval_in_page( $str, @args ) >>

=head2 C<< $mech->eval( $str, @args ) >>

  my ($value, $type) = $mech->eval( '2+2' );

Evaluates the given Javascript fragment in the
context of the web page.
Returns a pair of value and Javascript type.

This allows access to variables and functions declared
"globally" on the web page.

This method is special to WWW::Mechanize::PhantomJS.

=cut

sub eval_in_page {
    my ($self,$str,@args) = @_;

    # Report errors from scope of caller
    # This feels weirdly backwards here, but oh well:
    local @Selenium::Remote::Driver::CARP_NOT= (@Selenium::Remote::Driver::CARP_NOT, (ref $self)); # we trust this
    my $eval_in_sandbox = $self->driver->execute_script("return $str", @args);
};
*eval = \&eval_in_page;

=head2 C<< $mech->eval_in_phantomjs $code, @args >>

  $mech->eval_in_phantomjs(<<'JS', "Foobar/1.0");
      this.settings.userAgent= arguments[0]
  JS

Evaluates Javascript code in the context of PhantomJS.

This allows you to modify properties of PhantomJS.

=cut

sub eval_in_phantomjs {
    my ($self, $code, @args) = @_;
    #my $tab = $self->tab;

    $self->{driver}->{commands}->{'phantomExecute'}||= {
        'method' => 'POST',
        'url' => "session/:sessionId/phantom/execute"
    };

    my $params= {
        args => \@args,
        script => $code,
    };
    $self->driver->_execute_command({ command => 'phantomExecute' }, $params);
};

=head2 C<< $mech->PhantomJS_elementToJS >>

Returns the Javascript fragment to turn a Selenium::Remote::PhantomJS
id back to a Javascript object.

=cut

sub PhantomJS_elementToJS {
    <<'JS'
    function(id,doc_opt){
        var d = doc_opt || document;
        var c= d['$wdc_'];
        return c[id]
    };
JS
}

sub agent {
    my($self, $ua) = @_;
    # page.settings.userAgent = 'Mozilla/5.0 (Windows NT 5.1; rv:8.0) Gecko/20100101 Firefox/7.0';
    $self->eval_in_phantomjs(<<'JS', $ua);
       this.settings.userAgent= arguments[0] 
JS
}

# Render as png
=for png
 page.viewportSize = { width: 1024, height: 768 }
 page.open(address, function (status) {
    if (status == 'fail') {
       console.log('Unable to load the address! ' + address);
       phantom.exit();
       console.log('Unable to load the address! ' + address);
    } else {
     window.setTimeout(function () {
     page.clipRect = { top: 0, left: 0, width: 990, height: 745 };
     page.render(output);
     console.log(status);
     phantom.exit();
     }, 200);
    }

 });
=cut

sub events { [] };

sub DESTROY {
    #warn "Destroying " . ref $_[0];
    my $pid= delete $_[0]->{pid};
    #my $dr= delete $_[0]->{ driver };
    #if($dr) {
    #    $dr->quit;
    #};
    #warn "Killing $pid";
    kill 9 => $pid
        if $pid;
    %{ $_[0] }= (); # clean out all other held references
}

=head1 NAVIGATION METHODS

=head2 C<< $mech->get( $url, %options ) >>

  $mech->get( $url, ':content_file' => $tempfile );

Retrieves the URL C<URL>.

It returns a faked L<HTTP::Response> object for interface compatibility
with L<WWW::Mechanize>. It seems that Selenium and thus L<Selenium::Remote::Driver>
have no concept of HTTP status code and thus no way of returning the
HTTP status code.

Recognized options:

=over 4

=item *

C<< :content_file >> - filename to store the data in

=item *

C<< no_cache >> - if true, bypass the browser cache

=back

=cut

sub update_response {
    my( $self, $phantom_res ) = @_;

    my @headers= map {;@{$_}{qw(name value)}} @{ $phantom_res->{headers} };
    my $res= HTTP::Response->new( $phantom_res->{status}, $phantom_res->{statusText}, \@headers );

    # Should we fetch the response body?!

    delete $self->{ current_form };

    $self->{response} = $res
};

sub get {
    my ($self, $url, %options ) = @_;
    # We need to stringify $url so it can pass through JSON
    my $phantom_res= $self->driver->get( "$url" );

    $self->update_response( $phantom_res );
};

=head2 C<< $mech->get_local( $filename , %options ) >>

  $mech->get_local('test.html');

Shorthand method to construct the appropriate
C<< file:// >> URI and load it into Firefox. Relative
paths will be interpreted as relative to C<$0>.

This method accepts the same options as C<< ->get() >>.

This method is special to WWW::Mechanize::PhantomJS but could
also exist in WWW::Mechanize through a plugin.

B<Warning>: PhantomJs does not handle local files well. Especially
subframes do not get loaded properly.

=cut

sub get_local {
    my ($self, $htmlfile, %options) = @_;
    require Cwd;
    require File::Spec;
    my $fn= File::Spec->file_name_is_absolute( $htmlfile )
          ? $htmlfile
          : File::Spec->rel2abs(
                 File::Spec->catfile(dirname($0),$htmlfile),
                 Cwd::getcwd(),
             );
    $fn =~ s!\\!/!g; # fakey "make file:// URL"
    my $url= "file:/$fn";

    my $res= $self->get($url, %options);

    # PhantomJS is not helpful with its error messages for local URLs
    if( 0+$res->headers->header_field_names) {
        # We need to fake the content headers from <meta> tags too...
        # Maybe this even needs to go into ->get()
        $res->code( 200 );
    } else {
        $res->code( 400 ); # Must have been "not found"
    };
    $res
}

=head2 C<< $mech->post( $url, %options ) >>

  $mech->post( 'http://example.com',
      params => { param => "Hello World" },
      headers => {
        "Content-Type" => 'application/x-www-form-urlencoded',
      },
      charset => 'utf-8',
  );

Sends a POST request to C<$url>.

A C<Content-Length> header will be automatically calculated if
it is not given.

The following options are recognized:

=over 4

=item *

C<headers> - a hash of HTTP headers to send. If not given,
the content type will be generated automatically.

=item *

C<data> - the raw data to send, if you've encoded it already.

=back

=cut

sub post {
    my ($self, $url, %options) = @_;
    #my $b = $self->tab->{linkedBrowser};
    $self->clear_current_form;

    #my $flags = 0;
    #if ($options{no_cache}) {
    #  $flags = $self->repl->constant('nsIWebNavigation.LOAD_FLAGS_BYPASS_CACHE');
    #};
    #if (! exists $options{synchronize}) {
    #  $options{synchronize} = $self->events;
    #};
    #if( !ref $options{synchronize}) {
    #  $options{synchronize} = $options{synchronize}
    #                          ? $self->events
    #                          : []
    #};

    # If we don't have data, encode the parameters:
    if( !$options{ data }) {
        my $req= HTTP::Request::Common::POST( $url, $options{params} );
        #warn $req->content;
        carp "Faking content from parameters is not yet supported.";
        #$options{ data } = $req->content;
    };

    #$options{ charset } ||= 'utf-8';
    #$options{ headers } ||= {};
    #$options{ headers }->{"Content-Type"} ||= "application/x-www-form-urlencoded";
    #if( $options{ charset }) {
    #    $options{ headers }->{"Content-Type"} .= "; charset=$options{ charset }";
    #};

    # Javascript POST implementation taken from
    # http://stackoverflow.com/questions/133925/javascript-post-request-like-a-form-submit
    $self->eval(<<'JS', $url, $options{ params }, 'POST');
        function (path, params, method) {
            method = method || "post"; // Set method to post by default if not specified.

            // The rest of this code assumes you are not using a library.
            // It can be made less wordy if you use one.
            var form = document.createElement("form");
            form.setAttribute("method", method);
            form.setAttribute("action", path);

            for(var key in params) {
                if(params.hasOwnProperty(key)) {
                    var hiddenField = document.createElement("input");
                    hiddenField.setAttribute("type", "hidden");
                    hiddenField.setAttribute("name", key);
                    hiddenField.setAttribute("value", params[key]);

                    form.appendChild(hiddenField);
                 }
            }

            document.body.appendChild(form);
            form.submit();
        }
JS
    # Now, how to trick Selenium into fetching the response?
}

=head2 C<< $mech->add_header( $name => $value, ... ) >>

    $mech->add_header(
        'X-WWW-Mechanize-Firefox' => "I'm using it",
        Encoding => 'text/klingon',
    );

This method sets up custom headers that will be sent with B<every> HTTP(S)
request that Firefox makes.

Using multiple instances of WWW::Mechanize::Firefox objects with the same
application together with changed request headers will most likely have weird
effects. So don't do that.

Note that currently, we only support one value per header.

=cut

sub add_header {
    my ($self, @headers) = @_;
    use Data::Dumper;
    #warn Dumper $headers;
    
    while( my ($k,$v) = splice @headers, 0, 2 ) {
        $self->eval_in_phantomjs(<<'JS', , $k, $v);
            var h= this.customHeaders;
            h[arguments[0]]= arguments[1];
            this.customHeaders= h;
JS
    };
};

=head2 C<< $mech->delete_header( $name , $name2... ) >>

    $mech->delete_header( 'User-Agent' );
    
Removes HTTP headers from the agent's list of special headers. Note
that Firefox may still send a header with its default value.

=cut

sub delete_header {
    my ($self, @headers) = @_;
    
    $self->eval_in_phantomjs(<<'JS', @headers);
        var headers= this.customHeaders;
        for( var i = 0; i < arguments.length; i++ ) {
            delete headers[arguments[i]];
        };
        this.customHeaders= headers;
JS
};

=head2 C<< $mech->reset_headers >>

    $mech->reset_headers();

Removes all custom headers and makes Firefox send its defaults again.

=cut

sub reset_headers {
    my ($self) = @_;
    $self->eval_in_phantomjs('this.customHeaders= {}');
};

# If things get nasty, we could fall back to PhantomJS.webpage.plainText
# var page = require('webpage').create();
# page.open('http://somejsonpage.com', function () {
#     var jsonSource = page.plainText;
sub decoded_content {
    $_[0]->driver->get_page_source
};

# Also webPage.setContent() for ->update_html()
sub content {
    my ($self, %options) = @_;
    $options{ format } ||= 'html';
    my $format = delete $options{ format } || 'html';

    my $content;
    if( 'html' eq $format ) {
        $content= $self->driver->get_page_source
    } elsif ( $format eq 'text' ) {
        $content= $self->text;
    } else {
        $self->die( qq{Unknown "format" parameter "$format"} );
    };
};

=head2 C<< $mech->text() >>

    print $mech->text();

Returns the text of the current HTML content.  If the content isn't
HTML, $mech will die.

=cut

sub text {
    my $self = shift;
    
    # Waugh - this is highly inefficient but conveniently short to write
    # Maybe this should skip SCRIPT nodes...
    join '', map { $_->get_text() } $self->xpath('//*/text()');
}

=head2 C<< $mech->content_encoding() >>

    print "The content is encoded as ", $mech->content_encoding;

Returns the encoding that the content is in. This can be used
to convert the content from UTF-8 back to its native encoding.

=cut

sub content_encoding {
    my ($self) = @_;
    # Let's trust the <meta http-equiv first, and the header second:
    # Also, a pox on PhantomJS for not having lower-case or upper-case
    if(( my $meta )= $self->xpath( q{//meta[translate(@http-equiv,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')="content-type"]}, first => 1 )) {
        (my $ct= $meta->get_attribute('content')) =~ s/^.*;\s*charset=\s*//i;
        return $ct
            if( $ct );
    };
    $self->response->header('Content-Type');
};

=head2 C<< $mech->update_html( $html ) >>

  $mech->update_html($html);

Writes C<$html> into the current document. This is mostly
implemented as a convenience method for L<HTML::Display::MozRepl>.

=cut

sub update_html {
    my ($self,$content) = @_;
    $self->eval_in_phantomjs('this.setContent(arguments[0], arguments[1])', $content);
};

=head2 C<< $mech->base() >>

  print $mech->base;

Returns the URL base for the current page.

The base is either specified through a C<base>
tag or is the current URL.

This method is specific to WWW::Mechanize::Firefox

=cut

sub base {
    my ($self) = @_;
    (my $base) = $self->selector('base');
    $base = $base->{href}
        if $base;
    $base ||= $self->uri;
};

=head2 C<< $mech->content_type() >>

=head2 C<< $mech->ct() >>

  print $mech->content_type;

Returns the content type of the currently loaded document

=cut

sub content_type {
    my ($self) = @_;
    # Let's trust the <meta http-equiv first, and the header second:
    # Also, a pox on PhantomJS for not having lower-case or upper-case
    my $ct;
    if(my( $meta )= $self->xpath( q{//meta[translate(@http-equiv,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')="content-type"]}, first => 1 )) {
        $ct= $meta->get_attribute('content');
    };
    if(!$ct and my $r= $self->response ) {
        my $h= $r->headers;
        $ct= $h->header('Content-Type');
    };
    $ct =~ s/;.*$//;
    $ct
};

*ct = \&content_type;

=head2 C<< $mech->is_html() >>

  print $mech->is_html();

Returns true/false on whether our content is HTML, according to the
HTTP headers.

=cut

sub is_html {
    my $self = shift;
    return defined $self->ct && ($self->ct eq 'text/html');
}

=head2 C<< $mech->title() >>

  print "We are on page " . $mech->title;

Returns the current document title.

=cut

sub title {
    $_[0]->driver->get_title;
};

=head1 EXTRACTION METHODS

=head2 C<< $mech->links() >>

  print $_->text . " -> " . $_->url . "\n"
      for $mech->links;

Returns all links in the document as L<WWW::Mechanize::Link> objects.

Currently accepts no parameters. See C<< ->xpath >>
or C<< ->selector >> when you want more control.

=cut

%link_spec = (
    a      => { url => 'href', },
    area   => { url => 'href', },
    frame  => { url => 'src', },
    iframe => { url => 'src', },
    link   => { url => 'href', },
    meta   => { url => 'content', xpath => (join '',
                    q{translate(@http-equiv,'ABCDEFGHIJKLMNOPQRSTUVWXYZ',},
                    q{'abcdefghijklmnopqrstuvwxyz')="refresh"}), },
);
# taken from WWW::Mechanize. This should possibly just be reused there
sub make_link {
    my ($self,$node,$base) = @_;

    my $tag = lc $node->get_tag_name;
    my $url;
    if ($tag) {
        if( ! exists $link_spec{ $tag }) {
            carp "Unknown link-spec tag '$tag'";
            $url= '';
        } else {
            $url = $node->{ $link_spec{ $tag }->{url} };
        };
    };

    if ($tag eq 'meta') {
        my $content = $url;
        if ( $content =~ /^\d+\s*;\s*url\s*=\s*(\S+)/i ) {
            $url = $1;
            $url =~ s/^"(.+)"$/$1/ or $url =~ s/^'(.+)'$/$1/;
        }
        else {
            undef $url;
        }
    };

    if (defined $url) {
        my $res = WWW::Mechanize::Link->new({
            tag   => $tag,
            name  => $node->{name},
            base  => $base,
            url   => $url,
            text  => $node->{innerHTML},
            attrs => {},
        });

        $res
    } else {
        ()
    };
}

# Call croak or carp, depending on the C< autodie > setting
sub signal_condition {
    my ($self,$msg) = @_;
    if ($self->{autodie}) {
        croak $msg
    } else {
        carp $msg
    }
};

# Call croak on the C< autodie > setting if we have a non-200 status
sub signal_http_status {
    my ($self) = @_;
    if ($self->{autodie}) {
        if ($self->status and $self->status !~ /^2/ and $self->status != 0) {
            # there was an error
            croak ($self->response(headers => 0)->message || sprintf "Got status code %d", $self->status );
        };
    } else {
        # silent
    }
};

sub response { $_[0]->{response} };
*res = \&response;

=head2 C<< $mech->back( [$synchronize] ) >>

    $mech->back();

Goes one page back in the page history.

Returns the (new) response.

=cut

sub back {
    my ($self, $synchronize) = @_;
    $synchronize ||= (@_ != 2);
    if( !ref $synchronize ) {
        $synchronize = $synchronize
                     ? $self->events
                     : []
    };

    $self->_sync_call($synchronize, sub {
        $self->driver->go_back;
    });
}

=head2 C<< $mech->forward( [$synchronize] ) >>

    $mech->forward();

Goes one page forward in the page history.

Returns the (new) response.

=cut

sub forward {
    my ($self, $synchronize) = @_;
    $synchronize ||= (@_ != 2);
    if( !ref $synchronize ) {
        $synchronize = $synchronize
                     ? $self->events
                     : []
    };

    $self->_sync_call($synchronize, sub {
        $self->driver->go_forward;
    });
}

=head2 C<< $mech->uri() >>

    print "We are at " . $mech->uri;

Returns the current document URI.

=cut

sub uri {
    URI->new( $_[0]->driver->get_current_url )
}

=head2 C<< $mech->success() >>

    $mech->get('http://google.com');
    print "Yay"
        if $mech->success();

Returns a boolean telling whether the last request was successful.
If there hasn't been an operation yet, returns false.

This is a convenience function that wraps C<< $mech->res->is_success >>.

=cut

sub success {
    my $res = $_[0]->response( headers => 0 );
    $res and $res->is_success
}

=head2 C<< $mech->status() >>

    $mech->get('http://google.com');
    print $mech->status();
    # 200

Returns the HTTP status code of the response.
This is a 3-digit number like 200 for OK, 404 for not found, and so on.

=cut

sub status {
    my ($self) = @_;
    return $self->response( headers => 0 )->code
};

=head2 C<< $mech->selector( $css_selector, %options ) >>

  my @text = $mech->selector('p.content');

Returns all nodes matching the given CSS selector. If
C<$css_selector> is an array reference, it returns
all nodes matched by any of the CSS selectors in the array.

This takes the same options that C<< ->xpath >> does.

This method is implemented via L<WWW::Mechanize::Plugin::Selector>.

=cut

*selector = \&WWW::Mechanize::Plugin::Selector::selector;

=head2 C<< $mech->find_link_dom( %options ) >>

  print $_->{innerHTML} . "\n"
      for $mech->find_link_dom( text_contains => 'CPAN' );

A method to find links, like L<WWW::Mechanize>'s
C<< ->find_links >> method. This method returns DOM objects from
Firefox instead of WWW::Mechanize::Link objects.

Note that Firefox
might have reordered the links or frame links in the document
so the absolute numbers passed via C<n>
might not be the same between
L<WWW::Mechanize> and L<WWW::Mechanize::Firefox>.

Returns the DOM object as L<MozRepl::RemoteObject>::Instance.

The supported options are:

=over 4

=item *

C<< text >> and C<< text_contains >> and C<< text_regex >>

Match the text of the link as a complete string, substring or regular expression.

Matching as a complete string or substring is a bit faster, as it is
done in the XPath engine of Firefox.

=item *

C<< id >> and C<< id_contains >> and C<< id_regex >>

Matches the C<id> attribute of the link completely or as part

=item *

C<< name >> and C<< name_contains >> and C<< name_regex >>

Matches the C<name> attribute of the link

=item *

C<< url >> and C<< url_regex >>

Matches the URL attribute of the link (C<href>, C<src> or C<content>).

=item *

C<< class >> - the C<class> attribute of the link

=item *

C<< n >> - the (1-based) index. Defaults to returning the first link.

=item *

C<< single >> - If true, ensure that only one element is found. Otherwise croak
or carp, depending on the C<autodie> parameter.

=item *

C<< one >> - If true, ensure that at least one element is found. Otherwise croak
or carp, depending on the C<autodie> parameter.

The method C<croak>s if no link is found. If the C<single> option is true,
it also C<croak>s when more than one link is found.

=back

=cut

use vars '%xpath_quote';
%xpath_quote = (
    '"' => '\"',
    #"'" => "\\'",
    #'[' => '&#91;',
    #']' => '&#93;',
    #'[' => '[\[]',
    #'[' => '\[',
    #']' => '[\]]',
);

sub quote_xpath($) {
    local $_ = $_[0];
    s/(['"\[\]])/$xpath_quote{$1} || $1/ge;
    $_
};

sub find_link_dom {
    my ($self,%opts) = @_;
    my %xpath_options;

    for (qw(node document frames)) {
        # Copy over XPath options that were passed in
        if (exists $opts{ $_ }) {
            $xpath_options{ $_ } = delete $opts{ $_ };
        };
    };

    my $single = delete $opts{ single };
    my $one = delete $opts{ one } || $single;
    if ($single and exists $opts{ n }) {
        croak "It doesn't make sense to use 'single' and 'n' option together"
    };
    my $n = (delete $opts{ n } || 1);
    $n--
        if ($n ne 'all'); # 1-based indexing
    my @spec;

    # Decode text and text_contains into XPath
    for my $lvalue (qw( text id name class )) {
        my %lefthand = (
            text => 'text()',
        );
        my %match_op = (
            '' => q{%s="%s"},
            'contains' => q{contains(%s,"%s")},
            # Ideally we would also handle *_regex here, but PhantomJS XPath
            # does not support fn:matches() :-(
            #'regex' => q{matches(%s,"%s","%s")},
        );
        my $lhs = $lefthand{ $lvalue } || '@'.$lvalue;
        for my $op (keys %match_op) {
            my $v = $match_op{ $op };
            $op = '_'.$op if length($op);
            my $key = "${lvalue}$op";

            if (exists $opts{ $key }) {
                my $p = delete $opts{ $key };
                push @spec, sprintf $v, $lhs, $p;
            };
        };
    };

    if (my $p = delete $opts{ url }) {
        push @spec, sprintf '@href = "%s" or @src="%s"', quote_xpath $p, quote_xpath $p;
    }
    my @tags = (sort keys %link_spec);
    if (my $p = delete $opts{ tag }) {
        @tags = $p;
    };
    if (my $p = delete $opts{ tag_regex }) {
        @tags = grep /$p/, @tags;
    };
    my $q = join '|',
            map {
                my $xp= exists $link_spec{ $_ } ? $link_spec{$_}->{xpath} : undef;
                my @full = map {qq{($_)}} grep {defined} (@spec, $xp);
                if (@full) {
                    sprintf "//%s[%s]", $_, join " and ", @full;
                } else {
                    sprintf "//%s", $_
                };
            }  (@tags);
    #warn $q;

    my @res = $self->xpath($q, %xpath_options );

    if (keys %opts) {
        # post-filter the remaining links through WWW::Mechanize
        # for all the options we don't support with XPath

        my $base = $self->base;
        require WWW::Mechanize;
        @res = grep {
            WWW::Mechanize::_match_any_link_parms($self->make_link($_,$base),\%opts)
        } @res;
    };

    if ($one) {
        if (0 == @res) { $self->signal_condition( "No link found matching '$q'" )};
        if ($single) {
            if (1 <  @res) {
                $self->highlight_node(@res);
                $self->signal_condition(
                    sprintf "%d elements found found matching '%s'", scalar @res, $q
                );
            };
        };
    };

    if ($n eq 'all') {
        return @res
    };
    $res[$n]
}

=head2 C<< $mech->find_link( %options ) >>

  print $_->text . "\n"
      for $mech->find_link_dom( text_contains => 'CPAN' );

A method quite similar to L<WWW::Mechanize>'s method.
The options are documented in C<< ->find_link_dom >>.

Returns a L<WWW::Mechanize::Link> object.

This defaults to not look through child frames.

=cut

sub find_link {
    my ($self,%opts) = @_;
    my $base = $self->base;
    croak "Option 'all' not available for ->find_link. Did you mean to call ->find_all_links()?"
        if 'all' eq ($opts{n} || '');
    if (my $link = $self->find_link_dom(frames => 0, %opts)) {
        return $self->make_link($link, $base)
    } else {
        return
    };
};

=head2 C<< $mech->find_all_links( %options ) >>

  print $_->text . "\n"
      for $mech->find_link_dom( text_regex => qr/google/i );

Finds all links in the document.
The options are documented in C<< ->find_link_dom >>.

Returns them as list or an array reference, depending
on context.

This defaults to not look through child frames.

=cut

sub find_all_links {
    my ($self, %opts) = @_;
    $opts{ n } = 'all';
    my $base = $self->base;
    my @matches = map {
        $self->make_link($_, $base);
    } $self->find_all_links_dom( frames => 0, %opts );
    return @matches if wantarray;
    return \@matches;
};

=head2 C<< $mech->find_all_links_dom %options >>

  print $_->{innerHTML} . "\n"
      for $mech->find_link_dom( text_regex => qr/google/i );

Finds all matching linky DOM nodes in the document.
The options are documented in C<< ->find_link_dom >>.

Returns them as list or an array reference, depending
on context.

This defaults to not look through child frames.

=cut

sub find_all_links_dom {
    my ($self,%opts) = @_;
    $opts{ n } = 'all';
    my @matches = $self->find_link_dom( frames => 0, %opts );
    return @matches if wantarray;
    return \@matches;
};

=head2 C<< $mech->follow_link( $link ) >>

=head2 C<< $mech->follow_link( %options ) >>

  $mech->follow_link( xpath => '//a[text() = "Click here!"]' );

Follows the given link. Takes the same parameters that C<find_link_dom>
uses. In addition, C<synchronize> can be passed to (not) force
waiting for a new page to be loaded.

Note that C<< ->follow_link >> will only try to follow link-like
things like C<A> tags.

=cut

sub follow_link {
    my ($self,$link,%opts);
    if (@_ == 2) { # assume only a link parameter
        ($self,$link) = @_;
        $self->click($link);
    } else {
        ($self,%opts) = @_;
        _default_limiter( one => \%opts );
        $link = $self->find_link_dom(%opts);
        $self->click({ dom => $link, %opts });
    }
}

# We need to trace the path from the root element to every webelement
# because stupid GhostDriver/Selenium caches elements per document,
# and not globally, keyed by document. Switching the implied reference
# document makes lots of API calls fail :-(
sub activate_parent_container {
    my( $self, $doc )= @_;
    $self->activate_container( $doc, 1 );
};

sub activate_container {
    my( $self, $doc, $just_parent )= @_;
    my $driver= $self->driver;

    if( ! $doc->{__path}) {
        die "Invalid document without __path encountered. I'm sorry.";
    };
    # Activate the root window/frame
    #warn "Activating root frame:";
    #$driver->switch_to_frame();
    #warn "Activating root frame done.";

    for my $el ( @{ $doc->{__path} }) {
        #warn "Switching frames downwards ($el)";
        #warn "Tag: " . $el->get_tag_name;
        #use Data::Dumper;
        #warn Dumper $el;
        warn sprintf "Switching during path to %s %s", $el->get_tag_name, $el->get_attribute('src');
        $driver->switch_to_frame( $el );
    };
    
    if( ! $just_parent ) {
        warn sprintf "Activating container %s too", $doc->{id};
        # Now, unless it's the root frame, activate the container. The root frame
        # already is activated above.
        warn "Getting tag";
        my $tag= $doc->get_tag_name;
        #my $src= $doc->get_attribute('src');
        if( 'html' ne $tag and '' ne $tag) {
            #warn sprintf "Switching to final container %s %s", $tag, $src;
            $driver->switch_to_frame( $doc );
        };
        #warn sprintf "Switched to final/main container %s %s", $tag, $src;
    };
    #warn $self->driver->get_current_url;
    #warn $self->driver->get_title;
    #my $body= $doc->get_attribute('contentDocument');
    my $body= $driver->find_element('/*', 'xpath');
    if( $body ) {
        warn "Now active container: " . $body->get_attribute('innerHTML');
        #$body= $body->get_attribute('document');
        #warn $body->get_attribute('innerHTML');
    };
};

=head2 C<< $mech->xpath( $query, %options ) >>

    my $link = $mech->xpath('//a[id="clickme"]', one => 1);
    # croaks if there is no link or more than one link found

    my @para = $mech->xpath('//p');
    # Collects all paragraphs

    my @para_text = $mech->xpath('//p/text()', type => $mech->xpathResult('STRING_TYPE'));
    # Collects all paragraphs as text

Runs an XPath query in Firefox against the current document.

If you need more information about the returned results,
use the C<< ->xpathEx() >> function.

The options allow the following keys:

=over 4

=item *

C<< document >> - document in which the query is to be executed. Use this to
search a node within a specific subframe of C<< $mech->document >>.

=item *

C<< frames >> - if true, search all documents in all frames and iframes.
This may or may not conflict with C<node>. This will default to the
C<frames> setting of the WWW::Mechanize::Firefox object.

=item *

C<< node >> - node relative to which the query is to be executed. Note
that you will have to use a relative XPath expression as well. Use

  .//foo

instead of

  //foo

=item *

C<< single >> - If true, ensure that only one element is found. Otherwise croak
or carp, depending on the C<autodie> parameter.

=item *

C<< one >> - If true, ensure that at least one element is found. Otherwise croak
or carp, depending on the C<autodie> parameter.

=item *

C<< maybe >> - If true, ensure that at most one element is found. Otherwise
croak or carp, depending on the C<autodie> parameter.

=item *

C<< all >> - If true, return all elements found. This is the default.
You can use this option if you want to use C<< ->xpath >> in scalar context
to count the number of matched elements, as it will otherwise emit a warning
for each usage in scalar context without any of the above restricting options.

=item *

C<< any >> - no error is raised, no matter if an item is found or not.

=item *

C<< type >> - force the return type of the query.

  type => $mech->xpathResult('ORDERED_NODE_SNAPSHOT_TYPE'),

WWW::Mechanize::Firefox tries a best effort in giving you the appropriate
result of your query, be it a DOM node or a string or a number. In the case
you need to restrict the return type, you can pass this in.

The allowed strings are documented in the MDN. Interesting types are

  ANY_TYPE     (default, uses whatever things the query returns)
  STRING_TYPE
  NUMBER_TYPE
  ORDERED_NODE_SNAPSHOT_TYPE

=back

Returns the matched results.

You can pass in a list of queries as an array reference for the first parameter.
The result will then be the list of all elements matching any of the queries.

This is a method that is not implemented in WWW::Mechanize.

In the long run, this should go into a general plugin for
L<WWW::Mechanize>.

=cut

sub xpath {
    my( $self, $query, %options) = @_;

    if ('ARRAY' ne (ref $query||'')) {
        $query = [$query];
    };

    if( not exists $options{ frames }) {
        $options{ frames }= $self->{frames};
    };

    my $single = $options{ single };
    my $first  = $options{ one };
    my $maybe  = $options{ maybe };
    my $any    = $options{ any };
    my $return_first_element = ($single or $first or $maybe or $any );
    $options{ user_info }||= join "|", @$query;

    # Construct some helper variables
    my $zero_allowed = not ($single or $first);
    my $two_allowed  = not( $single or $maybe);

    # Sanity check for the common error of
    # my $item = $mech->xpath("//foo");
    if (! exists $options{ all } and not ($return_first_element)) {
        $self->signal_condition(join "\n",
            "You asked for many elements but seem to only want a single item.",
            "Did you forget to pass the 'single' option with a true value?",
            "Pass 'all => 1' to suppress this message and receive the count of items.",
        ) if defined wantarray and !wantarray;
    };

    my @res;

    # Save the current frame, because maybe we switch frames while searching
    # We should ideally save the complete path here, not just the current position
    if( $options{ document }) {
        warn sprintf "Document %s", $options{ document }->{id};
    };
    #my $original_frame= $self->current_frame;
    
    DOCUMENTS: {
        my $doc= $options{ document } || $self->document;
        
        # This stores the path to this document
        $doc->{__path}||= [];

        # @documents stores pairs of (containing document element, child element)
        my @documents= ($doc);

        # recursively join the results of sub(i)frames if wanted

        while (@documents) {
            my $doc = shift @documents;

            #$self->activate_container( $doc );

            my $q = join "|", @$query;
            #warn $q;
            
            my @found;
            # Now find the elements
            if ($options{ node }) {
                #$doc ||= $options{ node }->get_attribute( 'documentElement' );
                #if( $options{ document } and $options{ document }->get_tag_name =~ /^i?frame$/i) {
                #    $self->driver->switch_to_frame( $options{ document });
                #} elsif( $options{ document } and $options{ document }->get_tag_name =~ /^html$/i) {
                #    $self->driver->switch_to_frame();
                #} elsif( $options{ document }) {
                #    die sprintf "Don't know how to switch to a '%s'", $options{ document }->get_tag_name;
                #};
                @found= map { $self->driver->find_child_elements( $options{ node }, $_ => 'xpath' ) } @$query;
            } else {
                #warn "Collecting frames";
                #my $tag= $doc->get_tag_name;
                #warn "Searching $doc->{id} for @$query";
                @found= map { $self->driver->find_elements( $_ => 'xpath' ) } @$query;
                if( ! @found ) {
                    #warn "Nothing found matching @$query in frame";
                    #warn $self->content;
                    #$self->driver->switch_to_frame();
                };
                #$self->driver->switch_to_frame();
                #warn $doc->get_text;
            };
            
            # Remember the path to each found element
            for( @found ) {
                # We reuse the reference here instead of copying the list. So don't modify the list.
                $_->{__path}= $doc->{__path};
            };
            
            push @res, @found;
            
            # A small optimization to return if we already have enough elements
            # We can't do this on $return_first as there might be more elements
            #if( @res and $options{ return_first } and grep { $_->{resultSize} } @res ) {
            #    @res= grep { $_->{resultSize} } @res;
            #    last DOCUMENTS;
            #};
            use Data::Dumper;
            #warn Dumper \@documents;
            if ($options{ frames } and not $options{ node }) {
                #warn "Expanding subframes";
                #warn ">Expanding below " . $doc->get_tag_name() . ' - ' . $doc->get_attribute('title');
                #local $nesting .= "--";
                my @d; # = $self->expand_frames( $options{ frames }, $doc );
                #warn sprintf("Found %s %s pointing to %s", $_->get_tag_name, $_->{id}, $_->get_attribute('src')) for @d;
                push @documents, @d;
            };
        };
    };

    # Restore frame context
    #warn "Switching back";
    #$self->activate_container( $original_frame );

    #@res

    # Determine if we want only one element
    #     or a list, like WWW::Mechanize::Firefox

    if (! $zero_allowed and @res == 0) {
        $self->signal_condition( "No elements found for $options{ user_info }" );
    };
    if (! $two_allowed and @res > 1) {
        #$self->highlight_node(@res);
        warn $_->get_text() for @res;
        $self->signal_condition( (scalar @res) . " elements found for $options{ user_info }" );
    };

    $return_first_element ? $res[0] : @res

}

=head2 C<< $mech->by_id( $id, %options ) >>

  my @text = $mech->by_id('_foo:bar');

Returns all nodes matching the given ids. If
C<$id> is an array reference, it returns
all nodes matched by any of the ids in the array.

This method is equivalent to calling C<< ->xpath >> :

    $self->xpath(qq{//*[\@id="$_"], %options)

It is convenient when your element ids get mistaken for
CSS selectors.

=cut

sub by_id {
    my ($self,$query,%options) = @_;
    if ('ARRAY' ne (ref $query||'')) {
        $query = [$query];
    };
    $options{ user_info } ||= "id "
                            . join(" or ", map {qq{'$_'}} @$query)
                            . " found";
    $query = [map { qq{.//*[\@id="$_"]} } @$query];
    $self->xpath($query, %options)
}

=head2 C<< $mech->click( $name [,$x ,$y] ) >>

  $mech->click( 'go' );
  $mech->click({ xpath => '//button[@name="go"]' });

Has the effect of clicking a button (or other element) on the current form. The
first argument is the C<name> of the button to be clicked. The second and third
arguments (optional) allow you to specify the (x,y) coordinates of the click.

If there is only one button on the form, C<< $mech->click() >> with
no arguments simply clicks that one button.

If you pass in a hash reference instead of a name,
the following keys are recognized:

=over 4

=item *

C<selector> - Find the element to click by the CSS selector

=item *

C<xpath> - Find the element to click by the XPath query

=item *

C<dom> - Click on the passed DOM element

You can use this to click on arbitrary page elements. There is no convenient
way to pass x/y co-ordinates with this method.

=item *

C<id> - Click on the element with the given id

This is useful if your document ids contain characters that
do look like CSS selectors. It is equivalent to

    xpath => qq{//*[\@id="$id"]}

=item *

C<synchronize> - Synchronize the click (default is 1)

Synchronizing means that WWW::Mechanize::Firefox will wait until
one of the events listed in C<events> is fired. You want to switch
it off when there will be no HTTP response or DOM event fired, for
example for clicks that only modify the DOM.

You can pass in a scalar that is a false value to not wait for
any kind of event.

Passing in an array reference will use the array elements as
Javascript events to wait for.

Passing in any other true value will use the value of C<< ->events >>
as the list of events to wait for.

=back

Returns a L<HTTP::Response> object.

As a deviation from the WWW::Mechanize API, you can also pass a
hash reference as the first parameter. In it, you can specify
the parameters to search much like for the C<find_link> calls.

=cut

sub click {
    my ($self,$name,$x,$y) = @_;
    my %options;
    my @buttons;

    if (! defined $name) {
        croak("->click called with undef link");
    } elsif (ref $name and blessed($name) and $name->can('click')) {
        $options{ dom } = $name;
    } elsif (ref $name eq 'HASH') { # options
        %options = %$name;
    } else {
        $options{ name } = $name;
    };

    if (exists $options{ name }) {
        $name = quotemeta($options{ name }|| '');
        $options{ xpath } = [
                       sprintf( q{//*[(translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")="button" and @name="%s") or (translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")="input" and (@type="button" or @type="submit" or @type="image") and @name="%s")]}, $name, $name),
        ];
        if ($options{ name } eq '') {
            push @{ $options{ xpath }},
                       q{//*[(translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "button" or translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")="input") and @type="button" or @type="submit" or @type="image"]},
            ;
        };
        $options{ user_info } = "Button with name '$name'";
    };

    if (! exists $options{ synchronize }) {
        #$options{ synchronize } = $self->events;
    } elsif( ! ref $options{ synchronize }) {
        #$options{ synchronize } = $options{ synchronize }
        #                        ? $self->events
        #                        : [],
    };
    $options{ synchronize } ||= [];

    if ($options{ dom }) {
        @buttons = $options{ dom };
    } else {
        @buttons = $self->_option_query(%options);
    };

    $self->_sync_call(
        $options{ synchronize }, sub { # ,'abort'
            $buttons[0]->click();
        }
    );

    if (defined wantarray) {
        return $self->response
    };
}

# Internal method to run either an XPath, CSS or id query against the DOM
# Returns the element(s) found
my %rename = (
    xpath => 'xpath',
    selector => 'selector',
    id => 'by_id',
    by_id => 'by_id',
);

sub _option_query {
    my ($self,%options) = @_;
    my ($method,$q);
    for my $meth (keys %rename) {
        if (exists $options{ $meth }) {
            $q = delete $options{ $meth };
            $method = $rename{ $meth } || $meth;
        }
    };
    _default_limiter( 'one' => \%options );
    croak "Need either a name, a selector or an xpath key!"
        if not $method;
    return $self->$method( $q, %options );
};

# Return the default limiter if no other limiting option is set:
sub _default_limiter {
    my ($default, $options) = @_;
    if (! grep { exists $options->{ $_ } } qw(single one maybe all any)) {
        $options->{ $default } = 1;
    };
    return ()
};

# Internal convenience method for dipatching a call either synchronized
# or not
sub _sync_call {
    my ($self, $events, $cb) = @_;

    if (@$events) {
        $self->synchronize( $events, $cb );
    } else {
        $cb->();
    };
};

=head2 C<< $mech->click_button( ... ) >>

  $mech->click_button( name => 'go' );
  $mech->click_button( input => $mybutton );

Has the effect of clicking a button on the current form by specifying its
name, value, or index. Its arguments are a list of key/value pairs. Only
one of name, number, input or value must be specified in the keys.

=over 4

=item *

C<name> - name of the button

=item *

C<value> - value of the button

=item *

C<input> - DOM node

=item *

C<id> - id of the button

=item *

C<number> - number of the button

=back

If you find yourself wanting to specify a button through its
C<selector> or C<xpath>, consider using C<< ->click >> instead.

=cut

sub click_button {
    my ($self,%options) = @_;
    my $node;
    my $xpath;
    my $user_message;
    if (exists $options{ input }) {
        $node = delete $options{ input };
    } elsif (exists $options{ name }) {
        my $v = delete $options{ name };
        $xpath = sprintf( '//*[(translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "button" and @name="%s") or (translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")="input" and @type="button" or @type="submit" and @name="%s")]', $v, $v);
        $user_message = "Button name '$v' unknown";
    } elsif (exists $options{ value }) {
        my $v = delete $options{ value };
        $xpath = sprintf( '//*[(translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "button" and @value="%s") or (translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")="input" and (@type="button" or @type="submit") and @value="%s")]', $v, $v);
        $user_message = "Button value '$v' unknown";
    } elsif (exists $options{ id }) {
        my $v = delete $options{ id };
        $xpath = sprintf '//*[@id="%s"]', $v;
        $user_message = "Button name '$v' unknown";
    } elsif (exists $options{ number }) {
        my $v = delete $options{ number };
        $xpath = sprintf '//*[translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "button" or (translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "input" and @type="submit")][%s]', $v;
        $user_message = "Button number '$v' out of range";
    };
    $node ||= $self->xpath( $xpath,
                          node => $self->current_form,
                          single => 1,
                          user_message => $user_message,
              );
    if ($node) {
        $self->click({ dom => $node, %options });
    } else {

        $self->signal_condition($user_message);
    };

}

=head1 FORM METHODS

=head2 C<< $mech->current_form() >>

  print $mech->current_form->{name};

Returns the current form.

This method is incompatible with L<WWW::Mechanize>.
It returns the DOM C<< <form> >> object and not
a L<HTML::Form> instance.

The current form will be reset by WWW::Mechanize::PhantomJS
on calls to C<< ->get() >> and C<< ->get_local() >>,
and on calls to C<< ->submit() >> and C<< ->submit_with_fields >>.

=cut

sub current_form {
    my( $self, %options )= @_;
    # Find the first <FORM> element from the currently active element
    $self->{current_form};
}

sub clear_current_form {
    undef $_[0]->{current_form};
};

sub active_form {
    my( $self, %options )= @_;
    # Find the first <FORM> element from the currently active element
    my $focus= $self->driver->get_active_element;

    if( !$focus ) {
        warn "No active element, hence no active form";
        return
    };

    my $form= $self->xpath( './ancestor-or-self::FORM', node => $focus, maybe => 1 );

}

=head2 C<< $mech->form_name( $name [, %options] ) >>

  $mech->form_name( 'search' );

Selects the current form by its name. The options
are identical to those accepted by the L<< /$mech->xpath >> method.

=cut

sub form_name {
    my ($self,$name,%options) = @_;
    $name = quote_xpath $name;
    _default_limiter( single => \%options );
    $self->{current_form} = $self->selector("form[name='$name']",
        user_info => "form name '$name'",
        %options
    );
};

=head2 C<< $mech->form_id( $id [, %options] ) >>

  $mech->form_id( 'login' );

Selects the current form by its C<id> attribute.
The options
are identical to those accepted by the L<< /$mech->xpath >> method.

This is equivalent to calling

    $mech->by_id($id,single => 1,%options)

=cut

sub form_id {
    my ($self,$name,%options) = @_;

    _default_limiter( single => \%options );
    $self->{current_form} = $self->by_id($name,
        user_info => "form with id '$name'",
        %options
    );
};

=head2 C<< $mech->form_number( $number [, %options] ) >>

  $mech->form_number( 2 );

Selects the I<number>th form.
The options
are identical to those accepted by the L<< /$mech->xpath >> method.

=cut

sub form_number {
    my ($self,$number,%options) = @_;

    _default_limiter( single => \%options );
    $self->{current_form} = $self->xpath("(//form)[$number]",
        user_info => "form number $number",
        %options
    );
};

=head2 C<< $mech->form_with_fields( [$options], @fields ) >>

  $mech->form_with_fields(
      'user', 'password'
  );

Find the form which has the listed fields.

If the first argument is a hash reference, it's taken
as options to C<< ->xpath >>.

See also L<< /$mech->submit_form >>.

=cut

sub form_with_fields {
    my ($self,@fields) = @_;
    my $options = {};
    if (ref $fields[0] eq 'HASH') {
        $options = shift @fields;
    };
    my @clauses  = map { $self->element_query([qw[input select textarea]], { 'name' => $_ })} @fields;


    my $q = "//form[" . join( " and ", @clauses)."]";
    #warn $q;
    _default_limiter( single => $options );
    $self->{current_form} = $self->xpath($q,
        user_info => "form with fields [@fields]",
        %$options
    );
    #warn $form;
    $self->{current_form};
};

=head2 C<< $mech->forms( %options ) >>

  my @forms = $mech->forms();

When called in a list context, returns a list
of the forms found in the last fetched page.
In a scalar context, returns a reference to
an array with those forms.

The options
are identical to those accepted by the L<< /$mech->selector >> method.

The returned elements are the DOM C<< <form> >> elements.

=cut

sub forms {
    my ($self, %options) = @_;
    my @res = $self->selector('form', %options);
    return wantarray ? @res
                     : \@res
};

=head2 C<< $mech->field( $selector, $value, [,\@pre_events [,\@post_events]] ) >>

  $mech->field( user => 'joe' );
  $mech->field( not_empty => '', [], [] ); # bypass JS validation

Sets the field with the name given in C<$selector> to the given value.
Returns the value.

The method understands very basic CSS selectors in the value for C<$selector>,
like the L<HTML::Form> find_input() method.

A selector prefixed with '#' must match the id attribute of the input.
A selector prefixed with '.' matches the class attribute. A selector
prefixed with '^' or with no prefix matches the name attribute.

By passing the array reference C<@pre_events>, you can indicate which
Javascript events you want to be triggered before setting the value.
C<@post_events> contains the events you want to be triggered
after setting the value.

By default, the events set in the
constructor for C<pre_events> and C<post_events>
are triggered.

=cut

sub field {
    my ($self,$name,$value,$pre,$post) = @_;
    $self->get_set_value(
        name => $name,
        value => $value,
        pre => $pre,
        post => $post,
        node => $self->current_form,
    );
}

=head2 C<< $mech->value( $selector_or_element, [%options] ) >>

    print $mech->value( 'user' );

Returns the value of the field given by C<$selector_or_name> or of the
DOM element passed in.

The legacy form of

    $mech->value( name => value );

is also still supported but will likely be deprecated
in favour of the C<< ->field >> method.

For fields that can have multiple values, like a C<select> field,
the method is context sensitive and returns the first selected
value in scalar context and all values in list context.

=cut

sub value {
    if (@_ == 3) {
        my ($self,$name,$value) = @_;
        return $self->field($name => $value);
    } else {
        my ($self,$name,%options) = @_;
        return $self->get_set_value(
            node => $self->current_form,
            %options,
            name => $name,
        );
    };
};

=head2 C<< $mech->get_set_value( %options ) >>

Allows fine-grained access to getting/setting a value
with a different API. Supported keys are:

  pre
  post
  name
  value

in addition to all keys that C<< $mech->xpath >> supports.

=cut

sub _field_by_name {
    my ($self,%options) = @_;
    my @fields;
    my $name  = delete $options{ name };
    my $attr = 'name';
    if ($name =~ s/^\^//) { # if it starts with ^, it's supposed to be a name
        $attr = 'name'
    } elsif ($name =~ s/^#//) {
        $attr = 'id'
    } elsif ($name =~ s/^\.//) {
        $attr = 'class'
    };
    if (blessed $name) {
        @fields = $name;
    } else {
        _default_limiter( single => \%options );
        my $query = $self->element_query([qw[input select textarea]], { $attr => $name });
        #warn $query;
        @fields = $self->xpath($query,%options);
    };
    @fields
}

sub get_set_value {
    my ($self,%options) = @_;
    my $set_value = exists $options{ value };
    my $value = delete $options{ value };
    my $pre   = delete $options{pre}  || $self->{pre_value};
    my $post  = delete $options{post} || $self->{post_value};
    my $name  = delete $options{ name };
    my @fields = $self->_field_by_name(
                     name => $name,
                     user_info => "input with name '$name'",
                     %options );
    $pre = [$pre]
        if (! ref $pre);
    $post = [$post]
        if (! ref $post);

    if ($fields[0]) {
        my $tag = $fields[0]->get_tag_name();
        if ($set_value) {
            #for my $ev (@$pre) {
            #    $fields[0]->__event($ev);
            #};

            if ('select' eq $tag) {
                $self->select($fields[0], $value);
            } else {
                my $get= $self->PhantomJS_elementToJS();
                my $val= quotemeta($value);
                my $js= <<JS;
                    var g=$get;
                    var el=g("$fields[0]->{id}");
                    el.value="$val";
JS
                $js= quotemeta($js);
                $self->eval("eval('$js')"); # for some reason, Selenium/Ghostdriver don't like the JS as plain JS
            };

            #for my $ev (@$post) {
            #    $fields[0]->__event($ev);
            #};
        };
        # What about 'checkbox'es/radioboxes?

        # Don't bother to fetch the field's value if it's not wanted
        return unless defined wantarray;

        # We could save some work here for the simple case of single-select
        # dropdowns by not enumerating all options
        if ('SELECT' eq uc $tag) {
            my @options = $self->xpath('.//option', node => $fields[0] );
            my @values = map { $_->{value} } grep { $_->{selected} } @options;
            if (wantarray) {
                return @values
            } else {
                return $values[0];
            }
        } else {
            return $fields[0]->{value}
        };
    } else {
        return
    }
}

=head2 C<< $mech->submit( $form ) >>

  $mech->submit;

Submits the form. Note that this does B<not> fire the C<onClick>
event and thus also does not fire eventual Javascript handlers.
Maybe you want to use C<< $mech->click >> instead.

The default is to submit the current form as returned
by C<< $mech->current_form >>.

=cut

sub submit {
    my ($self,$dom_form) = @_;
    $dom_form ||= $self->current_form;
    if ($dom_form) {
        #warn sprintf "Submitting %s %s", $dom_form->get_tag_name, ref $dom_form;
        $dom_form->submit(); # why don't we ->synchronize here??
        #warn "Submitted";
        $self->signal_http_status;

        $self->clear_current_form;
        1;
    } else {
        croak "I don't know which form to submit, sorry.";
    }
};

=head2 C<< $mech->submit_form( %options ) >>

  $mech->submit_form(
      with_fields => {
          user => 'me',
          pass => 'secret',
      }
  );

This method lets you select a form from the previously fetched page,
fill in its fields, and submit it. It combines the form_number/form_name,
set_fields and click methods into one higher level call. Its arguments are
a list of key/value pairs, all of which are optional.

=over 4

=item *

C<< form => $mech->current_form() >>

Specifies the form to be filled and submitted. Defaults to the current form.

=item *

C<< fields => \%fields >>

Specifies the fields to be filled in the current form

=item *

C<< with_fields => \%fields >>

Probably all you need for the common case. It combines a smart form selector
and data setting in one operation. It selects the first form that contains
all fields mentioned in \%fields. This is nice because you don't need to
know the name or number of the form to do this.

(calls L<< /$mech->form_with_fields() >> and L<< /$mech->set_fields() >>).

If you choose this, the form_number, form_name, form_id and fields options
will be ignored.

=back

=cut

sub submit_form {
    my ($self,%options) = @_;
    
    my $form = delete $options{ form };
    my $fields;
    if (! $form) {
        if ($fields = delete $options{ with_fields }) {
            my @names = keys %$fields;
            warn Dumper \%options;
            $form = $self->form_with_fields( \%options, @names );
            if (! $form) {
                $self->signal_condition("Couldn't find a matching form for @names.");
                return
            };
        } else {
            $fields = delete $options{ fields } || {};
            $form = $self->current_form;
        };
    };
    
    if (! $form) {
        $self->signal_condition("No form found to submit.");
        return
    };
    $self->do_set_fields( form => $form, fields => $fields );
    $self->submit($form);
}

=head2 C<< $mech->set_fields( $name => $value, ... ) >>

  $mech->set_fields(
      user => 'me',
      pass => 'secret',
  );

This method sets multiple fields of the current form. It takes a list of
field name and value pairs. If there is more than one field with the same
name, the first one found is set. If you want to select which of the
duplicate field to set, use a value which is an anonymous array which
has the field value and its number as the 2 elements.

=cut

sub set_fields {
    my ($self, %fields) = @_;
    my $f = $self->current_form;
    if (! $f) {
        croak "Can't set fields: No current form set.";
    };
    $self->do_set_fields(form => $f, fields => \%fields);
};

sub do_set_fields {
    my ($self, %options) = @_;
    my $form = delete $options{ form };
    my $fields = delete $options{ fields };
    
    while (my($n,$v) = each %$fields) {
        if (ref $v) {
            ($v,my $num) = @$v;
            warn "Index larger than 1 not supported, ignoring"
                unless $num == 1;
        };
        
        $self->get_set_value( node => $form, name => $n, value => $v, %options );
    }
};

=head2 C<< $mech->expand_frames( $spec ) >>

  my @frames = $mech->expand_frames();

Expands the frame selectors (or C<1> to match all frames)
into their respective PhantomJS nodes according to the current
document. All frames will be visited in breadth first order.

This is mostly an internal method.

=cut

sub expand_frames {
    my ($self, $spec, $document) = @_;
    $spec ||= $self->{frames};
    my @spec = ref $spec ? @$spec : $spec;
    $document ||= $self->document;
    
    if (! ref $spec and $spec !~ /\D/ and $spec == 1) {
        # All frames
        @spec = qw( frame iframe );
    };
    
    # Optimize the default case of only names in @spec
    my @res;
    if (! grep {ref} @spec) {
        @res = $self->selector(
                        \@spec,
                        document => $document,
                        frames => 0, # otherwise we'll recurse :)
                    );
    } else {
        @res = 
            map { #warn "Expanding $_";
                    ref $_
                  ? $_
                  # Just recurse into the above code path
                  : $self->expand_frames( $_, $document );
            } @spec;
    }
    
    @res
};


=head2 C<< $mech->current_frame >>

    my $last_frame= $mech->current_frame;
    # Switch frame somewhere else
    
    # Switch back
    $mech->activate_container( $last_frame );

Returns the currently active frame as a WebElement.

This is mostly an internal method.

See also

L<http://code.google.com/p/selenium/issues/detail?id=4305>

Frames are currently not really supported./root/update-wan-ip --verbose --server ns.datenzoo.de -h mychat.dyn.datenzoo.de -f /root/Kdyn-datenzoo-de+157+57591.privatevers

=cut

sub current_frame {
    my( $self )= @_;
    my @res;
    my $current= $self->make_WebElement( $self->eval('window'));
    warn sprintf "Current_frame: bottom: %s", $current->{id};
    
    # Now climb up until the root window
    my $f= $current;
    my @chain;
    warn "Walking up to root document";
    while( $f= $self->driver->execute_script('return arguments[0].frameElement', $f )) {
        $f= $self->make_WebElement( $f );
        unshift @res, $f;
        warn sprintf "One more level up, now in %s", 
            $f->{id};
        warn $self->driver->execute_script('return arguments[0].title', $res[0]);
        unshift @chain,
            sprintf "Frame chain: %s %s", $res[0]->get_tag_name, $res[0]->{id};
        # Activate that frame
        $self->switch_to_parent_frame();
        warn "Going up once more, maybe";
    };
    warn "Chain complete";
    warn $_
        for @chain;
    
    # Now fake the element into 
    my $el= $self->make_WebElement( $current );
    for( @res ) {
        warn sprintf "Path has (web element) id %s", $_->{id};
    };
    $el->{__path}= \@res;
    $el
}

sub switch_to_parent_frame {
    #use JSON;
    my ( $self ) = @_;

    $self->{driver}->{commands}->{'switchToParentFrame'}||= {
        'method' => 'POST',
        'url' => "session/:sessionId/frame/parent"
    };

    #my $json_null = JSON::null;
    my $params;
    #$id = ( defined $id ) ? $id : $json_null;

    my $res    = { 'command' => 'switchToParentFrame' };
    return $self->driver->_execute_command( $res, $params );
}

sub make_WebElement {
    my( $self, $e )= @_;
    return $e
        if( blessed $e and $e->isa('Selenium::Remote::WebElement'));
    my $res= Selenium::Remote::WebElement->new( $e->{WINDOW} || $e->{ELEMENT}, $self->driver );
    croak "No id in " . Dumper $res
        unless $res->{id};
    
    $res
}

=head1 IMAGE METHODS

=head2 C<< $mech->content_as_png( [$tab, \%coordinates, \%target_size ] ) >>

    my $png_data = $mech->content_as_png();

    # Create scaled-down 480px wide preview
    my $png_data = $mech->content_as_png(undef, undef, { width => 480 });

Returns the given tab or the current page rendered as PNG image.

All parameters are optional. 

=over 4

=item *

C<$tab> defaults to the current tab.

=item *

If the coordinates are given, that rectangle will be cut out.
The coordinates should be a hash with the four usual entries,
C<left>,C<top>,C<width>,C<height>.

=item *

The target size of the image can also be given. It defaults to
the size of the image. The allowed parameters in the hash are

C<scalex>, C<scaley> - for specifying the scale, default is 1.0 in each direction.

C<width>, C<height> - for specifying the target size

If you want the resulting image to be 480 pixels wide, specify

    { width => 480 }

The height will then be calculated from the ratio of original width to
original height.

=back

This method is specific to WWW::Mechanize::Firefox.

Currently, the data transfer between Firefox and Perl
is done Base64-encoded. It would be beneficial to find what's
necessary to make JSON handle binary data more gracefully.

=cut

sub content_as_png {
    my ($self, $tab, $rect, $target_rect) = @_;
    #$tab ||= $self->tab;
    $rect ||= {};
    $target_rect ||= {};
    
    require MIME::Base64;
    my $png_base64 = $self->driver->screenshot();
    return MIME::Base64::decode_base64($png_base64);
};

=head2 C<< $mech->viewport_size >>

  print Dumper $mech->viewport_size;
  $mech->viewport_size({ width => 1388, height => 792 });

Returns (or sets) the new size of the viewport (the "window").

=cut

sub viewport_size {
    my( $self, $new )= @_;
    
    $self->eval_in_phantomjs( <<'JS', $new );
        var viewportSize= this.clipRect;
        if( arguments[0]) {
            this.clipRect= arguments[0];
        };
        viewportSize
JS
};

=head2 C<< $mech->element_as_png( $element ) >>

    my $shiny = $mech->selector('#shiny', single => 1);
    my $i_want_this = $mech->element_as_png($shiny);

Returns PNG image data for a single element

=cut

sub element_as_png {
    my ($self, $element) = @_;

    my $cliprect = $self->element_coordinates( $element );

    my $code = <<'JS';
       var old= this.clipRect;
       this.clipRect= arguments[0];
JS

    my $old= $self->eval_in_phantomjs( $code, $cliprect );
    my $png= $self->content_as_png();
    warn Dumper $old;
    $self->eval_in_phantomjs( $code, $old );
    $png
};

=head2 C<< $mech->element_coordinates( $element ) >>

    my $shiny = $mech->selector('#shiny', single => 1);
    my ($pos) = $mech->element_coordinates($shiny);
    print $pos->{left},',', $pos->{top};

Returns the page-coordinates of the C<$element>
in pixels as a hash with four entries, C<left>, C<top>, C<width> and C<height>.

This function might get moved into another module more geared
towards rendering HTML.

=cut

sub element_coordinates {
    my ($self, $element) = @_;
    my $cliprect = $self->eval('arguments[0].getBoundingClientRect()', $element );
};

1;