module zame.core.fs.mount;

import zame.core.fs.provider;

class MountManager {
    private IFsProvider[][string] mounts;

    void mount(string scheme, IFsProvider provider) {
        if ((scheme in mounts) is null) {
            mounts[scheme] = [];
        }
        mounts[scheme] ~= provider;
    }

    void unmount(string scheme, IFsProvider provider) {
        if (auto pList = scheme in mounts) {
            IFsProvider[] newList;
            foreach (p; *pList) {
                if (p !is provider) {
                    newList ~= p;
                }
            }
            if (newList.length == 0) {
                mounts.remove(scheme);
            } else {
                mounts[scheme] = newList;
            }
        }
    }
    
    void clear(string scheme) {
        mounts.remove(scheme);
    }

    IFsProvider[] getProviders(string scheme) {
        if (auto pList = scheme in mounts) {
            return *pList; 
        }
        return [];
    }

    bool isMounted(string scheme) const {
        if (auto pList = scheme in mounts) {
            return (*pList).length > 0;
        }
        return false;
    }

    string[] getSchemes() const {
        return cast(string[])mounts.keys;
    }
}
