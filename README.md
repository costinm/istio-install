# istio-helm

Fork of istio helm templates, with additional modularity.

## Separate namespaces

Pilot and gateways can be installed in separate namespaces, including with different versions 
This allows separation of admins, and using 'production' and 'canary' versions. 

## Additional test templates

A number of helm test setups are general-purpose and should be installable in any cluster, to confirm
Istio works properly and allow testing the specific install.


