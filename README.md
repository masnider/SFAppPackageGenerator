# SFAppPackageGenerator
Small basic utility in PS for generating a Service Fabric application package from a bunch of Service build output.
Intentionally implemented entirely outside of VS, and using no project system or SF APIs. Should be able to get included elsewhere/translated to other languages, etc

How to use:
- Update the params at the start of the script to point to the solution folder where the build output of the project is rooted
- Adjust other parameters to specify the desired output application type, version, and location
- Save and F5

Next Work Items:
- Allow selection of which service packages to include
- Get real build output folder detection
- Allow generation of versioned packages based on existing application package
- Allow generation of differential packages from existing base application packages