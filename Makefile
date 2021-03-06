
.PHONY : log install_buck build watch message targets audit debug test xcode_tests clean project audit

# Use local version of Buck
BUCK=tools/buck

log:
	echo "Make"

install_buck:
	curl https://jitpack.io/com/github/airbnb/buck/4bd1a08625454c5034eb6ef6193e94f9e6e62a62/buck-4bd1a08625454c5034eb6ef6193e94f9e6e62a62.pex --output tools/buck
	chmod u+x tools/buck

update_cocoapods:
	pod repo update
	pod install

build:
	$(BUCK) build //App:ExampleApp

build_release:
	$(BUCK) build //App:ExampleApp --config-file ./BuildConfigurations/Release.buckconfig

watch:
	$(BUCK) build //App:ExampleWatchAppExtension#watchsimulator-i386

message:
	$(BUCK) build //App:ExampleMessageExtension

debug:
	$(BUCK) install //App:ExampleApp --run --simulator-name 'iPhone XS'

debug_release:
	$(BUCK) install //App:ExampleApp --run --simulator-name 'iPhone XS' --config-file ./BuildConfigurations/Release.buckconfig

targets:
	$(BUCK) targets //...

ci: install_buck install_ruby_gems targets build test ui_test ruby_test project xcode_tests watch message
	echo "Done"


buck_out = $(shell $(BUCK) root)/buck-out
test:
	@rm -f $(buck_out)/tmp/*.profraw
	@rm -f $(buck_out)/gen/*.profdata
	$(BUCK) test //App:ExampleAppCITests --test-runner-env XCTOOL_TEST_ENV_LLVM_PROFILE_FILE="$(buck_out)/tmp/code-%p.profraw%15x" \
		--config custom.other_cflags="\$$(config custom.code_coverage_cflags)" \
		--config custom.other_cxxflags="\$$(config custom.code_coverage_cxxflags)" \
		--config custom.other_ldflags="\$$(config custom.code_coverage_ldflags)" \
		--config custom.other_swift_compiler_flags="\$$(config custom.code_coverage_swift_compiler_flags)"
	xcrun llvm-profdata merge -sparse "$(buck_out)/tmp/code-"*.profraw -o "$(buck_out)/gen/Coverage.profdata"
	xcrun llvm-cov report "$(buck_out)/gen/App/ExampleAppBinary#iphonesimulator-x86_64" -instr-profile "$(buck_out)/gen/Coverage.profdata" -ignore-filename-regex "Pods|Carthage|buck-out"

# Buck requires a different test-runner to run UI tests. `fbxctest` from FBSimulatorControl has a compatible CLI invocation and can be used as a drop-in replacement for `xctool` here.
fbxctest = tools/fbxctest/bin/fbxctest
ui_test:
	# Diable UI Test for now, because it's broken on Xcode 10.2
	# $(BUCK) test //App:XCUITests --config apple.xctool_path=$(fbxctest)

install_ruby_gems:
	bundle install --path vendor/bundle

ruby_test:
	buck_binary_path=tools/buck bundle exec rspec BuckLocal/ruby_scripts/ -I BuckLocal/ruby_scripts/

audit:
	$(BUCK) audit rules App/BUCK > Config/Gen/App-BUCK.py
	$(BUCK) audit rules Pods/BUCK > Config/Gen/Pods-BUCK.py

clean:
	rm -rf **/*.xcworkspace
	rm -rf **/*.xcodeproj
	$(BUCK) clean

kill_xcode:
	killall Xcode || true
	killall Simulator || true

xcode_tests: project
	xcodebuild build test -workspace App/ExampleApp.xcworkspace -scheme ExampleApp -destination 'platform=iOS Simulator,name=iPhone 8,OS=latest' | xcpretty && exit ${PIPESTATUS[0]}

project: clean
	$(BUCK) project //App:workspace

buck_local_project: clean
	bundle exec rake buck_local:generate_project buck_binary_path=$(BUCK) workspace_target='//App:workspace-buck-local' top_level_lib_target='//App:ExampleAppLibrary' xcworkspace='App/ExampleAppBuckLocal.xcworkspace'
	open App/ExampleAppBuckLocal.xcworkspace
