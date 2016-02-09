package TestWebInterface;

use qbit;

use base qw(QBit::WebInterface::Test QBit::Application);

use QBit::WebInterface::Routing;

use TestWebInterface::Controller::TestController path => 'test_controller';

TRUE;
