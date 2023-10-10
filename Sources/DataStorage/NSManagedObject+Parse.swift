//
//  NSManagedObject+Parse.swift
//
//
//  Created by Yauheni Fiadotau on 9.10.23.
//

import Foundation
import CoreData

public enum DataStorageParseError: Error {
    case uniqueKeyToManyRelationshipUnsupported
}

extension NSManagedObject {
    static public func update(withArrayOfDictionaries arrayOfDicts: [[String: Any]], inContext context: NSManagedObjectContext) -> [NSManagedObject] {
        let entity = entity()
        
        var arrayOfDicts = arrayOfDicts
        var result = [NSManagedObject]()
        
        if let uniqueAttribute = entity.uniqueAttribute {
            let values = arrayOfDicts.compactMap { $0[uniqueAttribute.importName] as? CVarArg }
            let existedObjects = (try? Self.objects(withPossibleValues: values, for: uniqueAttribute.name, inContext: context)) ?? []
            let dictsAndObjects: [([String : Any], NSManagedObject)] = existedObjects.compactMap { existedObject in
                guard let dictForObject = arrayOfDicts.first(where: { $0[uniqueAttribute.importName] == existedObject.value(forKey: uniqueAttribute.name) }) else { return nil }
                return (dictForObject, existedObject)
            }
            dictsAndObjects.forEach { dict, object in
                object.update(withDictionary: dict)
                result.append(object)
            }
            let usedDicts = dictsAndObjects.map { $0.0 }
            arrayOfDicts = arrayOfDicts.filter { dict in !usedDicts.contains { dict == $0 } }
        }
        
        result.append(contentsOf: arrayOfDicts
            .map { dictionary in
                let newObject = Self.init(context: context)
                newObject.update(withDictionary: dictionary)
                return newObject
            }
        )
        return result
    }
    
    static public func update(withDictionary dict: [String: Any], inContext context: NSManagedObjectContext) -> NSManagedObject {
        update(withArrayOfDictionaries: [dict], inContext: context)[.zero]
    }
    
    public func update(withDictionary dict: [String: Any]) {
        updateAttributes(withDictionary: dict)
        updateRelationships(withDictionary: dict)
    }
    
    private func updateAttributes(withDictionary dict: [String: Any]) {
        let attributes = entity.attributes
        
        attributes.forEach { attribute in
            if let valueInDictForAttribute = dict[attribute.importName] {
                setValue(Self.transformValue(valueInDictForAttribute, forAttribute: attribute), forKey: attribute.name)
            }
        }
    }
    
    private func updateRelationships(withDictionary dict: [String: Any]) {
        let relationships = entity.relationships
        
        relationships.forEach { relationship in
            guard let destinationEntity = relationship.destinationEntity, let destinationClass = NSClassFromString(destinationEntity.managedObjectClassName) as? NSManagedObject.Type, let managedObjectContext = managedObjectContext else { return }
            
            if relationship.isToMany {
                if let relationshipDictionaries = dict[relationship.importName] as? [[String: Any]] {
                    if relationship.isOrdered {
                        if let orderedSet = value(forKey: relationship.name) as? NSMutableOrderedSet {
                            if relationship.deleteNotUpdated {
                                let updatedObjects = destinationClass.update(withArrayOfDictionaries: relationshipDictionaries, inContext: managedObjectContext)
                                let objectsForRemove = orderedSet.compactMap { $0 as? NSManagedObject }.filter { !updatedObjects.contains($0) }
                                orderedSet.intersect(NSOrderedSet(objects: updatedObjects))
                                setValue(orderedSet, forKey: relationship.name)
                                objectsForRemove.forEach { managedObjectContext.delete($0) }
                            } else {
                                orderedSet.union(NSOrderedSet(objects: destinationClass.update(withArrayOfDictionaries: relationshipDictionaries, inContext: managedObjectContext)))
                                setValue(orderedSet, forKey: relationship.name)
                            }
                        } else {
                            setValue(NSOrderedSet(array: destinationClass.update(withArrayOfDictionaries: relationshipDictionaries, inContext: managedObjectContext)), forKey: relationship.name)
                        }
                    } else {
                        if let set = value(forKey: relationship.name) as? NSMutableSet {
                            if relationship.deleteNotUpdated {
                                let updatedObjects = destinationClass.update(withArrayOfDictionaries: relationshipDictionaries, inContext: managedObjectContext)
                                let objectsForRemove = set.compactMap { $0 as? NSManagedObject }.filter { !updatedObjects.contains($0) }
                                set.intersect(Set(updatedObjects))
                                setValue(set, forKey: relationship.name)
                                objectsForRemove.forEach { managedObjectContext.delete($0) }
                            } else {
                                set.union(Set(destinationClass.update(withArrayOfDictionaries: relationshipDictionaries, inContext: managedObjectContext)))
                                setValue(set, forKey: relationship.name)
                            }
                        } else {
                            setValue(NSSet(array: destinationClass.update(withArrayOfDictionaries: relationshipDictionaries, inContext: managedObjectContext)), forKey: relationship.name)
                        }
                    }
                }
            } else {
                if let relationshipDictionary = dict[relationship.importName] as? [String: Any] {
                    setValue(destinationClass.update(withDictionary: relationshipDictionary, inContext: managedObjectContext), forKey: relationship.name)
                }
            }
        }
    }
    
    @objc open class func transformValue(_ value: Any, forAttribute attribute: NSAttributeDescription) -> Any {
        switch attribute.attributeType {
        case .URIAttributeType:
            if let value = value as? String, let url = NSURL(string: value) {
                return url
            }
        case .dateAttributeType:
            if let value = value as? String, let date = value.date {
                return date
            }
        default: break
        }
        return value
    }
}
