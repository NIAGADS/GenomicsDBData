''' utils for processing lists / doing set operations on lists '''

from collections import OrderedDict, Counter


def qw(s, returnTuple=False):
    '''
    mimics perl's qw function
    usage: qw('a b c') will yield ['a','b','c']
    returnTuple: return a tuple if true, otherwise return list
    '''
    if returnTuple:
        return tuple(s.split())
    else:
        return s.split()
    

def is_equivalent_list(list1, list2):
    ''' test if two lists contain the same elements;
    order does not matter'''
    return Counter(list1) == Counter(list2)


def is_overlapping_list(list1, list2):
    ''' returns True if the intersection of the two lists is True
    i.e., at least one element in list2 is in list1
    '''
    return bool(set(list1) & set(list2))


def is_subset(list1, list2):
    ''' returns True if list1 is a subset of list2
    i.e., all elements in list1 are in list2'''
    return set(list1).issubset(list2)


def alphabetize_string_list(slist):
    ''' sorts a list of strings alphabetically
    takes a list or a string, but always returns a string
    '''
    if isinstance(slist, str):
        return ','.join(sorted(slist.split(',')))
    else:
        return ','.join(sorted(slist))


def list_to_indexed_dict(clist):
    ''' convert list to hash of value -> index '''
    return OrderedDict(zip(clist, range(1, len(clist) + 1)))
