---
title: "Kustomize and GitOps: The Good, the Bad, and the Ugly"
category:
  - essay
header:
  teaser: /assets/images/kustomize-good-bad-ugly/Gitops-Kustomize-Fig-1.png
tags:
  - gitops
  - automation
  - kustomize
  - helm
  - argocd
toc: true
published: true
---

_The Right Tool For the Wrong Job_

Teams adopting GitOps invariably face a handful of pivotal decisions in their path, such as the choice of GitOps framework and how to design repositories to match their deployment workflows.

In a Kubernetes-based shop, that framework is probably either Argo CD or Flux CD, which are adept at detecting and correcting configuration drift between the repositories and the target clusters.

| ![Two-part picture. The figure on the left shows a robot startled while looking at a difference between contents on a Git repository folder and the configuration of a Kubernetes cluster. The figure on the right shows the robot replicating the change on the Kubernetes cluster.](/assets/images/kustomize-good-bad-ugly/Gitops-Kustomize-Fig-1.png) |
|:--:|
| A GitOps framework’s primary job is to detect "drift" between the desired configuration in a Git repo and the actual settings in a deployment. |

## What You See Is Almost What You Get

While these frameworks can apply the literal contents of a Git repository to a target Kubernetes cluster, those contents are likely to need adjustments to fit most common scenarios.

For example, assume a system with five production environments where the only difference in the configuration for each cluster is the number of worker nodes. It would be challenging to maintain one complete copy of the folder per cluster over time, with authors mindlessly replicating changes and pull request reviewers droning over duplicate content.

| ![A picture of five file folders with four identical attributes and one tiny difference in the fifth attribute. Sticky figure scratching head while staring at folders.](/assets/images/kustomize-good-bad-ugly/Gitops-Kustomize-Fig-2.png) |
|:--:|
| Copying-pasting folder contents may be the fastest way to bootstrap a new environment but will make maintenance more challenging over time. |

These Kubernetes-based GitOps frameworks offer internal configuration management pipelines as a common strategy to avoid these tedious and error-prone repetitions. The pipelines transform the repository’s contents before applying the results to the destination — while Flux CD uses the term "pipelines," Argo CD refers to these transformations as "[build environments](https://argo-cd.readthedocs.io/en/stable/user-guide/build-environment/)."

The primary choices for transformation pipelines are Kustomize and Helm. Argo CD also supports the less popular [JSONNet framework](https://jsonnet.org/) and the concept of custom configuration management plugins (CMP.) JSONNet, with its object-oriented approach, is peculiar enough to deserve a separate closer look, while I have a word or two about CMPs towards the end.

## How Does Kustomize Work?

[Kustomize](https://kustomize.io/) uses a configuration file named "kustomization.yaml" to transform the contents of a directory or GitHub URL. In its simplest form, a "kustomization.yaml" file has the list of files from the source directory. Running the kustomize command-line interface with that file against a local folder or remote Git URL yields the contents of the files in that list.

| ![Folder with many YAML files and a file named "kustomization.yaml" with a bulleted list of a few of those files.](/assets/images/kustomize-good-bad-ugly/Gitops-Kustomize%203.png) |
|:--:|
| Kustomize uses a `kustomization.yaml` file and a base folder as sources. The CLI uses the file to decide which files to process and how to modify them. |

Kustomize’s capabilities grow from there, with [features](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) such as adding a set of annotations to all resources, generating new ConfigMaps and Secrets based on a seed file, modifying select portions of resources, and a few others.

Kustomize meets most imaginable configuration scenarios, as long as you are willing to put effort into specific areas. The question addressed in later sections is whether that effort pays off during regular interactions with the repository, such as authoring and reviewing pull requests.

## Helm Charts. The basics

Helm charts offer a higher-level abstraction than Kustomize, centered around the concept of "[Charts](https://helm.sh/docs/chart_template_guide/getting_started/)." At the core, a chart is a combination of files in a folder named "templates" and a "values.yaml" file. The "templates" folder contains Kubernetes resources, just like in Kustomize, but Helm can substitute optional templating statements inside each file with contents from various sources.

The [templating statements](https://helm.sh/docs/chart_template_guide/values_files/) can be as simple as a reference to a variable declared in the "values.yaml" file but can grow in complexity with flow controls, built-in functions, and named templates.

| ![Picture of a folder with a "templates" folder and a "values.yaml" file. The "templates" folder has many files in it. An inset of one of the files shows a couple of variable declarations and the value declared inside "values.yaml"](/assets/images/kustomize-good-bad-ugly/Gitops-Kustomize-Fig-3-Helm.png) |
|:---:|
| Helm transformations revolve around the `templates` folder and `values.yaml`. Helm finds templating statements and replaces them with values such as variables and other resource contents. |

After covering the basics of Kustomize and Helm, it is time to explore the Good, the Bad, and the Ugly of each approach in the context of a GitOps practice.

## The Good #1: Kustomize as a Library Cart

If your organization has a curated library of configuration resources, Kustomize is an ideal companion to select elements from that library. Add only the filenames of the resources you need into a kustomization.yaml file, indicate the Git URL (and "ref" !) of the folders containing the resources, and the Kustomize pipeline inside Argo CD or Flux CD will apply those resources to the target system.

Although Helm can achieve the same result of applying select resources from an extensive repository, both [Argo](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/) and [Flux](https://fluxcd.io/flux/guides/helmreleases/) require the creation of a wrapper resource for each Chart.

## The Good #2: What You See (In the Files) Is What You Get

One of the core premises of a GitOps practice is to manage system configuration using a Git repository. While it is virtually impossible to represent all configuration levers for a Kubernetes cluster, let alone for the entire infrastructure, Kustomize’s design relies solely on configuration files as the input to manage configuration.

As evidence of Kustomize’s opinionated approach to data sources, it only supports [reusing system environment variables in ConfigMaps and Secrets](https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-kustomize/)*. The only way to replace a variable mentioned in other resource types is to provide another file with that value.

__No ambiguity__. To take its opinionated approach a step further, Kustomize requires that repository owners be precise about the "address" of changes, specifying the type of resource and the respective location of patches and replacements. That specificity virtually eliminates ambiguity and the potential for a change accidentally causing side-effects elsewhere in the results of a kustomize transformation.

As a result, one can be confident about the resulting configuration after applying Kustomize to the contents of a GitOps repository by looking solely at the repository and without consulting any other source.

| ![Side-by-side drawing of a folder with a Kubernetes Job resource and a kustomization.yaml file containing a "resources" element selecting the file for the Job resource and a long "replacements" field targeting a secret deep inside a "container" element inside the Job specification.](/assets/images/kustomize-good-bad-ugly/Gitops-Kustomize-Fig-4-Addressing.png) |
|:---:|
| Kustomize's design calls for a deterministic selection of resources based on a precise selection of resource types, names, and field locations. |

Contrast that certainty with Helm’s approach to templating, where the invoker of the Helm command-line interface can override any variable in the "values.yaml" file with a command-line parameter. Helm propagates that value to all occurrences of the variable name anywhere in the Chart, with the semantics of simple text replacement and not a hint of type awareness.

While convenient, that flexibility means a pull request reviewer may feel inclined to reject a change if they cannot tell whether a variable value in the Chart may compromise the system, such as a variable name representing the role reference in a ClusterRoleBinding resource.

## The Bad: Mixing Filesystems With Kubernetes Concepts

While I appreciate the simplicity of a file-based approach to select resources, there is some conceptual back-and-forth between filesystems and Kubernetes CRDs when reading a Kustomize-based repository.

Surely, we can expect a GitOps practitioner to know their way around both concepts, but that kind of context-switching reduces productivity for pull request reviewers.

__Is it a file or a resource?__ For example, the entry-level construct ["resources"](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/resource/) locates resources by filename. At the same time, an element such as ["patches"](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/patches/) follows the conceptual model of Kubernetes patches, with meta-references to fields in a custom resource definition. Sitting in between filesystems and patches, we find elements such as "replacements," combining some addressability concepts from patching and what looks like JSON selectors.

| ![Sticky figure looks at three files: a.yaml containing a ConfigMap resource, b.yaml containing another ConfigMap resource, and a kustomization.yaml file containing a "resources" element referencing both files. The kustomization.yaml file has a "replacements" section referencing a "ConfigMap", making the sticky figure wonder which of a.yaml or b.yaml contain matching resources.](/assets/images/kustomize-good-bad-ugly/Gitops-Kustomize-Fig-4-Kustomize-Resource-orFile.png) |
|:---:|
| A kustomization.yaml file contains a mixture of concepts, with some constructs based on filenames ("resources") and other constructs based on Go-templating ("replacements") and a few based on Kubernetes custom resources (some forms of "patches.") |

I know Kustomize advocates may become proficient at the context-switching and consider it just a matter of course when working with configuration management in Kubernetes. Naturally, I would not expect Kustomize to use a constrained file-based approach like the "sed" syntax to modify a file. Still, it is hard to gloss over how reading a Kustomize file calls for the somewhat challenging ability to mentally assemble these different concepts, especially when I look at the most common workarounds:

> "You could run the kustomize CLI to see the results instead of trying to read the source."

At that point, I am already going outside the GitOps tooling to work around the problem, cloning the branch for pull requests and figuring out the correct parameters to invoke kustomize.

> "A CI/CD action could run the kustomize CLI and show the differences in the context of the pull request review."

A bot showing the outcome of the kustomize output between the source and target branches, even when integrated into something like the "Checks" tab of a pull request in GitHub, does not tell me the source files and lines where the changes originated. At that point, that is a review of a deployment plan instead of a pull request review.

## The Ugly #1: Dealing With Variable Replacements

The same opinionated philosophy that makes Kustomize-based repositories self-contained and prescriptive during operations makes Kustomize brittle when dealing with everyday situations.

__Replace with "replacements"__. With ["vars" being deprecated](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/vars/), one must pause to take in the complexity of its functional replacement, which is coincidentally and unironically named ["replacements."](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/replacements/)

I appreciate how a block of code like the one below leaves no margin of doubt about what it will do, but it is hard to overlook the many keywords and metadata references spent on addressing the one field to be replaced.

| ![Developer sitting at a table and frantically coding a large block of a YAML resource with multiple lines of statements to replace a single value in a Job resource.](/assets/images/kustomize-good-bad-ugly/GitOps-Kustomize-Lots-of-Yaml.png) |
|:---:|
| Kustomize sometimes makes simple tasks, like replacing a variable inside a resource, labor-intensive and difficult to maintain. |

## The Ugly #2: File Names Are (Almost) Forever

The precision with which Kustomize addresses file locations in a repository is its undoing when the time comes for refactoring files and folders.

If you have an overlay folder containing a "kustomization.yaml" file, which includes a "resources" section referencing a few files in a base folder, any change to a filename in that base folder may break the overlay folder.

__Overlay 3rd-party bases at your peril__. Addressing filename changes is simpler when you own both the overlay and base folders. You presumably have complete control over making changes to both folders simultaneously during a refactoring cycle.

| ![Sticky figure representing the author of a pull request struggling to move two enormous folders (twice his size) to the right.](/assets/images/kustomize-good-bad-ugly/Gitops-Kustomize-Last.png) |
|:---:|
| Refactoring resources across folders and files is a brittle process, where developers must exercise extreme care in matching every name change with the contents of other files. |

A less common and dangerous scenario is when the refactoring of a base folder splits the contents of a file into multiple files while preserving the original file's name. For instance, someone may have placed an extraneous "ClusterRoleBinding" in a file named "roles.yaml", then versioned the repository, and then refactored that role binding resource into a dedicated "bindings.yaml" file on the next release.

That is the kind of change that can easily go unnoticed in a "kustomize" invocation (the "resources" section has the name of a file that still exists,) requiring exquisite levels of attention when updating the reference to a newer version of the "base" folder.

## The Ugly #3: The Magic Hybrid

Argo CD's [configuration management plugins](https://argo-cd.readthedocs.io/en/stable/operator-manual/config-management-plugins/) allow an admin to provide Argo custom code to run the transformation pipeline. One of the samples offered in the guides is a blend of [Kustomize and Helm](https://github.com/argoproj/argocd-example-apps/tree/master/plugins/kustomized-helm).

At first glance, the idea makes sense: If Kustomize and Helm have strengths and weaknesses, combine both, right?

Not really.

Combining both means practitioners have to design (and observe) the boundary where Kustomize ends and Helm starts. For instance, the design may call for the "kustomization.yaml" file only allowing the usage of the "resources" clause, deferring everything else to Helm.But what stops a new team member, unaware of that boundary, from using a "replacements" or "patch" annotation to avoid creating another Helm chart?

| ![Two-part figure. The tree representation of a folder containing a kustomization.yaml file and two Helm charts is on the left. The kustomization.yaml file contains a "resources" section referencing one of the Helm charts. The right side of the picture has two robots carrying two objects, with one of the robots standing on the back of the first.](/assets/images/kustomize-good-bad-ugly/Gitops-Kustomize-Fig-Hybrid.png) |
|:---:|
| A custom configuration management plugin can run different commands in a sequence. With great flexibility comes the great need to design, document, and enforce bespoke workflows. |

Between the overhead of working with two overlapping technologies, constantly toeing the imaginary line between the two, and having to correct eventual boundary crosses, the total cost of ownership for the hybrid approach offsets any productivity gain in leveraging Kustomize in small corners of the repository.

There may still be good cases for using those plugins, but making Kustomize and Helm work together isn't one of them.

---

## Conclusion

Kustomize offers advantages when dealing with file selection scenarios, but resource contents invariably need alterations. With Kustomize, those alterations mean pull request reviewers staring at stretches of "patches" and "replacements" blocks, ultimately trying to run small Kustomize pipelines in their heads.

Pull request reviewers may often ponder their career choices while deciphering the meaning of ["JSON 6902](https://kubectl.docs.kubernetes.io/references/kustomize/glossary/#patchjson6902)", and authors may find themselves wondering whether a custom resource definition tolerates the patch they would like to apply to a resource.

For a discipline like GitOps, which requires frequent adjustments to large folder structures before an agent of some sort can deploy the results to a target cluster, I think Kustomize requires disproportionately greater attention and effort than working with Helm charts.

While I can enjoy the occasional mental gymnastic involved in reconstructing a Helm chart as a Kustomize-based file structure, I remain hard-pressed to pick Kustomize over Helm for all but the most limited use cases in a busy GitOps practice.

---

## Credits

Thanks to __Joe Bowbeer__ for highlighting [Kustomize’s ability to source environment variables for ConfigMaps and Secrets](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/#configmapgenerator).

## References

- [GitOps Guide to the Galaxy (Ep 23): Directory structure battles (YouTube)](https://www.youtube.com/watch?v=HDg5vh97zmI)
- [The GitOps Files — Repository design pitfalls (Medium)](https://dnastacio.medium.com/gitops-repositories-the-right-way-part-1-mapping-strategies-6409dff758b5)
