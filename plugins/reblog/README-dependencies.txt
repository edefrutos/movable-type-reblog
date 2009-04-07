REQUIRED PERL LIBRARIES:

The following libraries are required for use of Reblog. Reblog will not be available in Movable Type unless these libraries are installed.

DateTime
Date::Parse

Additionally, parsing enclosures requires the use of Switch, and Reblog will die if it tries to do this and Switch.pm is unavailable.

OPTIONAL PERL LIBRARIES:

The following libraries are optional. If both are present, Reblog will attempt to parse even entries which are not valid XML. This includes, among other things, feeds that include high-bit ASCII characters (such as curly quotes) or entities that are valid in HTML but invalid in XML unless specifically declared (such as "&apos;"). Many of these feeds can be parsed if XML::Liberal and XML::LibXML are available.

XML::LibXML
XML::Liberal
