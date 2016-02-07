package TestWebInterface;

use qbit;

use base qw(QBit::WebInterface::Test QBit::WebInterface::Routing QBit::Application);
# Order for QBit::WebInterface and QBit::WebInterface::REST not important

use TestWebInterface::Controller::TestController path => 'test_controller';

TRUE;
