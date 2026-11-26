// Extract visible deposition moves from Bambu Studio's annotated G-code.
#include <algorithm>
#include <array>
#include <cmath>
#include <cctype>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>

struct Point { double x = 0, y = 0, z = 0; };
struct Segment { float ax, ay, az, bx, by, bz, width, height, tool; };
static_assert(sizeof(Segment) == 36);
using Params = std::array<double, 26>;
constexpr double pi = 3.14159265358979323846;

static bool begins(const std::string &s, const char *prefix) { return s.rfind(prefix, 0) == 0; }
static bool exterior(const std::string &s) {
    return s == "Outer wall" || s == "External perimeter" || s == "Overhang wall" ||
           s == "Overhang perimeter" || s == "Top surface" || s == "Bottom surface" ||
           s == "Top solid infill" || s == "Bottom solid infill" || s == "Bridge" ||
           s == "Bridge infill" || s == "Gap infill" || s == "Gap fill" || s == "Ironing";
}

class Reader {
    std::ofstream out;
    bool visible = false, xyzRelative = false, eRelative = false, xyPlane = true;
    bool toolchange = false, wipe = false;
    double e = 0, width = .42, height = .2;
    int tool = 0;
    Point pos;
    unsigned count = 0;
    void segment(Point a, Point b) {
        if (std::hypot(b.x-a.x, b.y-a.y) < .0001) return;
        if (++count > 4000000) throw std::runtime_error("toolpath_limit");
        Segment s{float(a.x),float(a.y),float(a.z),float(b.x),float(b.y),float(b.z),
                  float(width),float(height),float(tool)};
        out.write(reinterpret_cast<const char*>(&s), sizeof(s));
    }
    void arc(Point a, Point b, const Params &p, bool clockwise) {
        const auto get = [&](char k){return p[k-'A'];};
        const auto sweepFrom = [&](double cx,double cy){
            double sweep = std::atan2(b.y-cy,b.x-cx)-std::atan2(a.y-cy,a.x-cx);
            if (clockwise && sweep >= -1e-10) sweep -= 2*pi;
            if (!clockwise && sweep <= 1e-10) sweep += 2*pi;
            return sweep;
        };
        double cx,cy;
        if (std::isfinite(get('I')) || std::isfinite(get('J'))) {
            cx = a.x + (std::isfinite(get('I')) ? get('I') : 0);
            cy = a.y + (std::isfinite(get('J')) ? get('J') : 0);
        } else if (std::isfinite(get('R'))) {
            double dx=b.x-a.x, dy=b.y-a.y, len=std::hypot(dx,dy), r=get('R');
            if (len<.0001 || 2*std::abs(r)<len-.001) {segment(a,b);return;}
            double offset=std::sqrt(std::max(0.,r*r-len*len/4))/len;
            if (clockwise != (r<0)) offset=-offset;
            cx=(a.x+b.x)/2-dy*offset; cy=(a.y+b.y)/2+dx*offset;
        } else { segment(a,b); return; }
        double radius=std::hypot(a.x-cx,a.y-cy), sweep=sweepFrom(cx,cy);
        if (std::isfinite(get('P')) && get('P')>1)
            sweep += (clockwise ? -1 : 1)*2*pi*(std::min(64.,get('P'))-1);
        double angle=std::atan2(a.y-cy,a.x-cx);
        double step=2*std::acos(std::clamp(1-.025/std::max(radius,.026),-1.,1.));
        int n=std::clamp(int(std::ceil(std::abs(sweep)/std::max(.015,step))),1,8192);
        Point prev=a;
        for (int i=1;i<=n;i++) {
            double t=double(i)/n, v=angle+t*sweep;
            Point next=i==n ? b : Point{cx+radius*std::cos(v),cy+radius*std::sin(v),a.z+t*(b.z-a.z)};
            segment(prev,next); prev=next;
        }
    }
public:
    explicit Reader(const char *path): out(path,std::ios::binary) {out.exceptions(std::ios::badbit|std::ios::failbit);}
    void line(std::string &s) {
        if (s.empty()) return;
        if (s.back()=='\r') s.pop_back();
        if (s[0]==';') {
            if (begins(s,"; FEATURE: ")) visible=exterior(s.substr(11));
            else if (begins(s,";TYPE:")) visible=exterior(s.substr(6));
            else if (begins(s,"; LINE_WIDTH: ")) width=std::clamp(std::atof(s.c_str()+14),.03,5.);
            else if (begins(s,"; LAYER_HEIGHT: ")) height=std::clamp(std::atof(s.c_str()+16),.015,3.);
            else if (s=="; CP TOOLCHANGE START") toolchange=true;
            else if (s=="; CP TOOLCHANGE END") toolchange=false;
            else if (s=="; WIPE_START") wipe=true;
            else if (s=="; WIPE_END") wipe=false;
            else if (s=="; CHANGE_LAYER" || s==";LAYER_CHANGE" || s=="; MACHINE_END_GCODE_START") visible=false;
            return;
        }
        const char *q=s.c_str();
        while (*q==' ' || *q=='\t') ++q;
        char kind=*q;
        if ((kind!='G' && kind!='M' && kind!='T') || !std::isdigit(static_cast<unsigned char>(q[1]))) return;
        char *end;
        long code=std::strtol(q+1,&end,10);
        if (*end=='.') return;
        if (kind=='T') {if(code>=0 && code<255) tool=int(code); return;}
        if (kind=='M') {if(code==82 || code==83) eRelative=(code==83);return;}
        if (code==90 || code==91) {xyzRelative=code==91;return;}
        if (code>=17 && code<=19) {xyPlane=code==17;return;}
        if (code!=92 && (code<0 || code>3)) return;
        Params p; p.fill(std::numeric_limits<double>::quiet_NaN());
        for (q=end; *q && *q!=';';) {
            char k=*q++;
            if(k<'A' || k>'Z') continue;
            double v=std::strtod(q,&end);
            if(q!=end && std::isfinite(v) && std::abs(v)<1e8) p[k-'A']=v;
            q=end;
        }
        const auto coord=[&](char k,double old,bool relative){
            double v=p[k-'A']; return std::isfinite(v) ? v+(relative?old:0) : old;
        };
        Point a=pos;
        pos={coord('X',pos.x,code!=92 && xyzRelative),coord('Y',pos.y,code!=92 && xyzRelative),coord('Z',pos.z,code!=92 && xyzRelative)};
        double oldE=e; e=coord('E',e,code!=92 && eRelative);
        if (code==92 || e<=oldE+.0000001 || !visible || toolchange || wipe) return;
        if (code<2) segment(a,pos);
        else if (xyPlane) arc(a,pos,p,code==2);
    }
    void finish(){out.close(); if(!count) throw std::runtime_error("no_surface");}
};
int main(int argc,char **argv) {
    if(argc!=3) return 2;
    try {
        std::ifstream input(argv[1]); if(!input) throw std::runtime_error("cannot_open");
        Reader reader(argv[2]); std::string line;
        while(std::getline(input,line)) reader.line(line);
        if(input.bad()) throw std::runtime_error("read_interrupted");
        reader.finish(); return 0;
    } catch(const std::exception &e){std::cerr<<e.what();return 1;}
}
