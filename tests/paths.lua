-- Resolve repository sources from this helper, independent of the caller's cwd.
local filename=debug.getinfo(1,"S").source:sub(2)
local directory=filename:match("^(.*[/\\])") or ""
local P={root=directory.."../"}
function P.source(name)return P.root.."hammerspoon/"..name end
package.path=P.source("?.lua")..";"..package.path
return P
