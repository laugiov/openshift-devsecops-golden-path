import jenkins.model.Jenkins
import jenkins.plugins.git.GitSCMSource
import org.jenkinsci.plugins.workflow.libs.GlobalLibraries
import org.jenkinsci.plugins.workflow.libs.LibraryConfiguration
import org.jenkinsci.plugins.workflow.libs.SCMSourceRetriever

def jenkins = Jenkins.getInstance()

// Library configuration
def libraryName = 'golden-path'
def defaultVersion = 'main'
def libraryPath = '/var/jenkins_home/shared-library'

println "Configuring Golden Path Shared Library..."

// Create SCM source pointing to local directory
def scmSource = new GitSCMSource(
    'golden-path-library',
    "file://${libraryPath}",
    '', // credentials
    '*', // includes
    '', // excludes
    true // ignore on push
)

// Create library configuration
def retriever = new SCMSourceRetriever(scmSource)
def libraryConfig = new LibraryConfiguration(libraryName, retriever)
libraryConfig.setDefaultVersion(defaultVersion)
libraryConfig.setImplicit(false)
libraryConfig.setAllowVersionOverride(true)

// Get GlobalLibraries descriptor
def globalLibraries = jenkins.getDescriptorByType(GlobalLibraries.class)

// Check if library already exists
def existingLibraries = globalLibraries.getLibraries() ?: []
def libraryExists = existingLibraries.any { it.name == libraryName }

if (!libraryExists) {
    def newLibraries = new ArrayList(existingLibraries)
    newLibraries.add(libraryConfig)
    globalLibraries.setLibraries(newLibraries)
    jenkins.save()
    println "Golden Path Shared Library configured successfully!"
} else {
    println "Golden Path Shared Library already exists."
}

return "Done"
