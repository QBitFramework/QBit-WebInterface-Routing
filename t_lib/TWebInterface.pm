package TWebInterface;

use qbit;

use base qw(QBit::WebInterface QBit::Application);

use QBit::WebInterface::Routing;

use TWebInterface::Controller::TestController path => 'test_controller';

TRUE;
