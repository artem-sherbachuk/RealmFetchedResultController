//
//  RealmFetchedResultController.swift
//  HKClient
//
//  Created by Artem Sherbachuk (UKRAINE) artemsherbachuk@gmail.com on 7/8/17.
//

import RealmSwift

final class RealmFetchedResultController<T: Object> {
    
    let realm: Realm
    
    typealias ChangesClosure = ((RealmCollectionChange<Results<T>>)->Void)?
    
    private var onChanges: ChangesClosure
    
    var fetchedObjects: Results<T> {
        willSet {
            // we need to stop tracking notifications before changing fetchedObjects
            stopTrackingNotifications()
        }
        didSet {
            setupNotifications()
        }
    }
    
    var predicate: NSPredicate? {
        didSet {
            if oldValue != predicate {
                guard let predicate = predicate else {
                    self.fetchedObjects = realm.objects(T.self)
                    return
                }
                self.fetchedObjects = realm.objects(T.self).filter(predicate)
                
                if let sortDescriptors = sortDescriptors {
                    let sorted = self.fetchedObjects.sorted(by: sortDescriptors)
                    self.fetchedObjects = sorted
                }
                createSections(sectionKeyPath: sectionsKeyPath)
                self.onChanges?(RealmCollectionChange.initial(fetchedObjects))
            }
        }
    }
    
    var sortDescriptors: [SortDescriptor]? {
        didSet {
            guard let sortDescriptors = sortDescriptors else {
                return
            }
            
            let sorted = self.fetchedObjects.sorted(by: sortDescriptors)
            self.fetchedObjects = sorted
            
            createSections(sectionKeyPath: sectionsKeyPath)
            self.onChanges?(RealmCollectionChange.initial(fetchedObjects))
        }
    }
    
    ///sectionValue : objects
    private(set) var sections = [AnyHashable: Results<T>]()
    
    ///sectionsKeyPath. The property of model object wich will divide and create a sections.
    private(set) var sectionsKeyPath: String?
    
    private var notificationToken: NotificationToken?
    
    
    /// fetchRequest the request. sectionsKeyPath the property on model object wich will divide and create a sections by filter operation on fetchedObjects collection.
    init(realm: Realm, _ fetchRequest: RealmFetchRequest<T>, sectionsKeyPath: String?) {
        self.realm = realm
        self.predicate = fetchRequest.predicate
        self.sortDescriptors = fetchRequest.sortDescriptors
        self.sectionsKeyPath = sectionsKeyPath
        
        if let predicate = predicate {
            let filtered = realm.objects(T.self).filter(predicate)
            self.fetchedObjects = filtered
        } else {
            self.fetchedObjects = realm.objects(T.self)
        }
        
        if let sortDescriptors = sortDescriptors {
            let sorted = self.fetchedObjects.sorted(by: sortDescriptors)
            self.fetchedObjects = sorted
        }
        
        createSections(sectionKeyPath: self.sectionsKeyPath)
    }
    
    convenience init(realm: Realm, _ predicate: NSPredicate? = nil,
                     sortDescriptors: [SortDescriptor]? = nil,
                     sectionsKeyPath: String? = nil) {
        let fetchRequest = RealmFetchRequest<T>(predicate, sortDescriptors)
        self.init(realm:realm, fetchRequest, sectionsKeyPath: sectionsKeyPath)
    }
    
    deinit {
        stopTrackingNotifications()
        onChanges = nil
    }
    
    private func setupNotifications() {
        notificationToken = fetchedObjects.observe{ [weak self] changes in
            if let sectionsKeyPath = self?.sectionsKeyPath {
                self?.createSections(sectionKeyPath: sectionsKeyPath)
            }
            self?.onChanges?(changes)
        }
    }
    
    private func stopTrackingNotifications() {
        if notificationToken != nil {
            notificationToken?.invalidate()
            notificationToken = nil
        }
    }
    
    func updatePredicate(_ predicate: NSPredicate, andSectionKey sectionKey: String?) {
        sectionsKeyPath = sectionKey
        
        if self.predicate == predicate {
            createSections(sectionKeyPath: sectionsKeyPath)
        } else {
            self.predicate = predicate
        }
    }
    
    func onChanges(completion: @escaping (RealmCollectionChange<Results<T>>) -> Void) {
        stopTrackingNotifications()
        setupNotifications()
        self.onChanges = completion
    }
    
    func sectionKeyForSection(_ section: Int) -> AnyHashable? {
        return sectionKeys[safe: section]
    }
    
    func objectsForSection(section: Int) -> Results<T>? {
        if let key = sectionKeys[safe: section] {
            return sections[key]
        }
        
        return nil
    }
    
    func objectForIndexPath(indexPath: IndexPath) -> T? {
        let sectionIndex = indexPath.section
        let rowIndex = indexPath.row
        let sectionObjects = objectsForSection(section: sectionIndex)
        
        if sectionObjects == nil {
            let object = fetchedObjects[safe: rowIndex]
            return object?.isInvalidated == true ? nil : object
        } else {
            let object = sectionObjects?[safe: rowIndex]
            return object?.isInvalidated == true ? nil : object
        }
    }
    
    private var sectionKeys = [AnyHashable]()
    private func createSections(sectionKeyPath: String?) {
        guard let sectionsKeyPath = sectionsKeyPath else { return }
        
        var sections = [AnyHashable]()
        
        let set = Set(fetchedObjects.value(forKeyPath: sectionsKeyPath) as! [AnyHashable])
        if let setStrings = set as? Set<String> {
            sections = setStrings.sorted()
        } else if let setInt = set as? Set<Int> {
            sections = setInt.sorted()
        } else if let setInt64 = set as? Set<Int64> {
            sections = setInt64.sorted()
        }
        
        sectionKeys = sections
        
        self.sections = [:]
        for (_, sectionValue) in sectionKeys.enumerated() {
            let sectionItems = fetchedObjects.filter("\(sectionsKeyPath) == %@", sectionValue)
            self.sections[sectionValue] = sectionItems
        }
    }
}

final class RealmFetchRequest<T: Object> {
    var predicate: NSPredicate?
    var sortDescriptors: [SortDescriptor]?
    let type: T.Type
    
    init(_ predicate: NSPredicate? = nil, _ sortDescriptors: [SortDescriptor]? = nil) {
        self.predicate = predicate
        self.type = T.self
        self.sortDescriptors = sortDescriptors
    }
}

extension Collection {
    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Iterator.Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
