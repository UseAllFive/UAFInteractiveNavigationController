Pod::Spec.new do |s|
  s.name         = "UAFInteractiveNavigationController"
  s.version      = "0.1.3"
  s.summary      = "UAFInteractiveNavigationController makes life easier."
  s.description  = <<-DESC
                     UAFInteractiveNavigationController mirrors
                     UINavigationController behavior, but combines it with the
                     scroll-and-snap transition behavior of
                     UIPageViewController. It is meant for apps not using the
                     custom view-controller transitions iOS7.
                   DESC
  s.homepage     = "http://useallfive.github.io/UAFInteractiveNavigationController"
  s.license      = "MIT"
  s.authors      = { "Peng Wang"   => "peng@pengxwang.com" }
  s.source       = { :git => "https://github.com/UseAllFive/UAFInteractiveNavigationController.git",
                     :tag => "0.1.3" }
  s.platform     = :ios, '5.0'
  s.requires_arc = true
  s.source_files = 'UAFInteractiveNavigationController'
  s.dependency     'UAFToolkit/Utility'
  s.dependency     'UAFToolkit/UIKit'
  s.dependency     'UAFToolkit/Boilerplate'
  s.dependency     'UAFToolkit/Navigation'
end
