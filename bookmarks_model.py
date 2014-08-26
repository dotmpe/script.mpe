from sqlalchemy import *
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship, backref, sessionmaker

from taxus.util import SessionMixin


SqlBase = declarative_base()

def get_session(dbref, initialize=False):
    engine = create_engine(dbref)
    SqlBase.metadata.bind = engine
    if initialize:
        log.info("Applying SQL DDL to DB %s..", dbref)
        SqlBase.metadata.create_all()  # issue DDL create 
        log.note('Updated schema for %s to %s', dbref, 'X')
    session = sessionmaker(bind=engine)()
    return session


class Domain(SqlBase, SessionMixin):
    __tablename__ = 'domains'

    host_id = Column('id', Integer, primary_key=True)

    name = Column(String(255), nullable=False, index=True, unique=True)

    date_added = Column(DateTime, index=True, nullable=False)
    deleted = Column(Boolean, index=True, default=False)
    date_deleted = Column(DateTime)


class Locator(SqlBase, SessionMixin):
    __tablename__ = 'ids_lctr'

    lctr_id = Column('id', Integer, primary_key=True)

    global_id = Column(String(255), index=True, unique=True, nullable=False)

    date_added = Column(DateTime, index=True, nullable=False)
    deleted = Column(Boolean, index=True, default=False)
    date_deleted = Column(DateTime)

#ref = Column(String(255), index=True, unique=True)
# XXX: varchar(255) would be much too small for many (web) URL locators 
    ref = Column(Text(2048), index=True, unique=True)

    domain_id = Column(Integer, ForeignKey('domains.id'))
    domain = relationship('Domain', primaryjoin="Locator.domain_id==Domain.domain_id",
            backref='locations')


class Bookmark(SqlBase, SessionMixin):

    """
    A textual annotation with a short and long descriptive label,
    a sequence of tags, the regular set of dates, 
    """

    __tablename__ = 'bm'

    bm_id = Column('id', Integer, primary_key=True)

    name = Column(String(255), nullable=False, index=True, unique=True)

    date_added = Column(DateTime, index=True, nullable=False)
    deleted = Column(Boolean, index=True, default=False)
    date_deleted = Column(DateTime)

    ref_id = Column(Integer, ForeignKey('ids_lctr.id'))
    ref = relationship(Locator, primaryjoin=Locator.lctr_id==ref_id)

    extended = Column(Text(65535))#, index=True)
    "Textual annotation of the referenced resource. "
    public = Column(Boolean(), index=True)
    "Private or public. "
    tags = Column(Text(10240))
    "Comma-separated list of all tags. "


models = [ 
        Domain, 
        Locator, 
        Bookmark 
    ]

