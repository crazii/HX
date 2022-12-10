#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <sys/segments.h>
#include <dpmi.h>

const char* VENDOR_HDPMI = "HDPMI";    //vendor string
typedef struct VendorEntry
{
    uint32_t edi;
    uint16_t es;
}ENTRY;

static const int DEBUG_IN = 0x0addface;
static int DEBUG_OUT = 0;

int trap(void)
{
    int port = 0, out = 0, value = 0;
    asm(
    "mov %%edx, %0 \n\t"
    "mov %%ecx, %1 \n\t"
    "mov %%eax, %2 \n\t"
    :"=m"(port),"=m"(out),"=m"(value)
    ::"memory"
    );
    if(out)
    {
        DEBUG_OUT &= ~(0xFF << (port-0x388)*8);
        DEBUG_OUT |= (value&0xFF) << ((port-0x388)*8);
    }
    return (!out) ? (DEBUG_IN >> (port-0x388)*8) : value;
}

void __attribute__((naked)) trap_wrapper(void)
{
    trap();
    asm("lret"); //retf
}

void test1()
{
    DEBUG_OUT = 0x5A5A5A5A;
    asm("mov $0x388, %dx \n\t"
    "mov $0xdeadbeef, %eax \n\t"
    "out %al, %dx \n\t");
    printf("OUT dx, al: %08x\n", DEBUG_OUT);
}

void test2()
{
    DEBUG_OUT = 0x5A5A5A5A;
    asm("mov $0x388, %dx \n\t"
    "mov $0xdeadbeef, %eax \n\t"
    "out %ax, %dx \n\t");
    printf("OUT dx, ax: %08x\n", DEBUG_OUT);
}

void test3()
{
    DEBUG_OUT = 0x5A5A5A5A;
    asm("mov $0x388, %dx \n\t"
    "mov $0xdeadbeef, %eax \n\t"
    "out %eax, %dx \n\t");
    printf("OUT dx, eax: %08x\n", DEBUG_OUT);
}

void test4()
{
    int val = 0;
    asm("mov $0x388, %%dx \n\t"
    "mov $0xA5A5A5A5, %%eax \n\t"
    "in %%dx, %%al \n\t"
    "mov %%eax, %0 \n\t"
    : "=m"(val));
    printf("IN al, dx: %08x\n", val);
}

void test5()
{
    int val = 0;
    asm("mov $0x388, %%dx \n\t"
    "mov $0xA5A5A5A5, %%eax \n\t"
    "in %%dx, %%ax \n\t"
    "mov %%eax, %0 \n\t"
    : "=m"(val));
    printf("IN ax, dx: %08x\n", val);
}

void test6()
{
    int val = 0;
    asm("mov $0x388, %%dx \n\t"
    "mov $0xA5A5A5A5, %%eax \n\t"
    "in %%dx, %%eax \n\t"
    "mov %%eax, %0 \n\t"
    : "=m"(val));
    printf("IN eax, dx: %08x\n", val);
}

int InstallTrap(const ENTRY* entry, int start, int end, void(*handler)(void))
{
    int handle = 0;
    int count = end - start + 1;
    const ENTRY ent = *entry; //avoid gcc using ebx
    asm(
    "push %%ebx \n\t"
    "push %%esi \n\t"
    "push %%edi \n\t"
    "mov %1, %%esi \n\t"
    "mov %2, %%edi \n\t"
    "xor %%ecx, %%ecx \n\t"
    "mov %%cs, %%cx \n\t"
    "mov %%ds, %%bx \n\t"
    "mov %3, %%edx \n\t"
    "mov $6, %%eax \n\t" //ax=6, port trap
    "lcall *%4\n\t"
    "pop %%edi \n\t"
    "pop %%esi \n\t"
    "pop %%ebx \n\t"
    "jc 1f \n\t"
    "mov %%eax, %0 \n\t"
    "1: nop \n\t"
    :"=m"(handle)
    :"m"(start),"m"(count),"m"(handler),"m"(ent)
    :"eax","ecx","edx"
    );
    return handle;
}

int GetVendorEntry(ENTRY* entry)
{
    int result = 0;
    asm(
    "push %%es \n\t"
    "push %%esi \n\t"
    "push %%edi \n\t"
    "xor %%eax, %%eax \n\t"
    "xor %%edi, %%edi \n\t"
    "mov %%di, %%es \n\t"
    "mov $0x168A, %%ax \n\t"
    "mov %3, %%esi \n\t"
    "int $0x2F \n\t"
    "mov %%es, %%cx \n\t" //entry->es & entry->edi may use register esi & edi
    "mov %%edi, %%edx \n\t" //save edi to edx and pop first
    "pop %%edi \n\t"
    "pop %%esi \n\t"
    "pop %%es \n\t"
    "mov %%eax, %0 \n\t"
    "mov %%cx, %1 \n\t"
    "mov %%edx, %2 \n\t"
    : "=r"(result),"=m"(entry->es), "=m"(entry->edi)
    : "m"(VENDOR_HDPMI)
    : "eax", "ecx", "edx"
    );
    return (result&0xFF) == 0; //al=0 to succeed
}

int main()
{
    ENTRY entry = {0};
    if(!GetVendorEntry(&entry))
    {
        puts("failed to get vendor entry point.\n");
        return 1;
    }
    printf("HDPMI vendor entry: %04x:%08x\n", entry.es, entry.edi);

    unsigned long csbase = 0;
    __dpmi_get_segment_base_address(_my_cs(), &csbase);
    #if 0 //debug addr break
    printf("FUNC ADDR: %08x\n", csbase + (uintptr_t)&InstallTrap);
    system("pause");
    #endif
    
    if(InstallTrap(&entry, 0x388, 0x38B, &trap_wrapper) == 0)
    {
        puts("failed to install io trap.\n");
        return 1;
    }

    #if 1 //debug addr break
    printf("FUNC ADDR: %08x\n", csbase + (uintptr_t)&test1);
    system("pause");
    #endif
    test1();
    test2();
    test3();
    test4();
    test5();
    test6();
    return 0;
}