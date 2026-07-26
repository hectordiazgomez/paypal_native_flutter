Pod::Spec.new do |s|
  s.name             = 'paypal_native_flutter'
  s.version          = '0.1.0'
  s.summary          = 'Native PayPal card payments and web checkout for Flutter.'
  s.description      = 'Flutter bindings for PayPal official Android and iOS SDKs. Custom native card checkout and SDK-managed PayPal web checkout with server-created Orders v2 payments.'
  s.homepage         = 'https://github.com/yourorg/paypal_native_flutter'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'You' => 'you@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.platform         = :ios, '14.0'
  s.dependency 'Flutter'
  s.dependency 'PayPal/CardPayments', '= 2.0.1'
  s.dependency 'PayPal/PayPalWebPayments', '= 2.0.1'
  s.swift_version    = '5.9'
end
